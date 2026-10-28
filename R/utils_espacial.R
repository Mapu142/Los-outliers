# ==============================================================================
# R/utils_espacial.R
# Funciones espaciales: vecinos kNN, Moran global y local (permutaciones), mapas.
# Requiere: R/config.R, R/tema.R y los paquetes sf, dplyr, tibble, ggplot2 cargados.
# No ejecuta nada al cargarse.
# ------------------------------------------------------------------------------
# Decisión de diseño: Moran y LISA se implementan aquí con álgebra explícita (pocas
# líneas, sin depender de cambios de versión de spdep) y el script 05 las COMPARA con
# spdep::moran.test() como verificación cruzada.
# ==============================================================================

# Proyección de área igual para mapas mundiales (Equal Earth; requiere PROJ >= 7)
CRS_MAPA <- "+proj=eqearth"

NIVELES_LISA <- c("Alto-Alto", "Bajo-Bajo", "Alto-Bajo", "Bajo-Alto", "No significativo")

# ---- Vecinos: k más cercanos por distancia de círculo máximo ----------------
# pts: sf de puntos (lon/lat, EPSG:4326) con columna iso3, una fila por país.
# Devuelve un objeto de clase "nb" (lista de índices), compatible con spdep.
vecinos_knn <- function(pts, k = 5L) {
  stopifnot(nrow(pts) > k)
  d <- sf::st_distance(pts)                       # metros (esfera, requiere s2 activo)
  d <- matrix(as.numeric(d), nrow = nrow(pts))
  diag(d) <- Inf
  nb <- lapply(seq_len(nrow(d)), function(i) sort(order(d[i, ])[seq_len(k)]))
  attr(nb, "region.id") <- as.character(pts$iso3)
  class(nb) <- "nb"
  nb
}

# Matriz de pesos estandarizada por filas (cada fila suma 1)
matriz_w <- function(nb) {
  n <- length(nb)
  W <- matrix(0, n, n)
  for (i in seq_len(n)) W[i, nb[[i]]] <- 1 / length(nb[[i]])
  W
}

# ---- Moran global con prueba de permutación (bilateral) ---------------------
moran_global <- function(x, W, nsim = 999L) {
  stopifnot(!anyNA(x), length(x) == nrow(W))
  n <- length(x)
  z <- x - mean(x)
  den <- sum(z^2)
  I <- sum(z * (W %*% z)) / den
  p <- NA_real_
  if (nsim > 0) {
    zp <- vapply(seq_len(nsim), function(s) sample(z), numeric(n))   # n x nsim
    Isim <- colSums(zp * (W %*% zp)) / den
    p <- min(1, 2 * (min(sum(Isim >= I), sum(Isim <= I)) + 1) / (nsim + 1))
  }
  list(I = as.numeric(I), esperado = -1 / (n - 1), p = p, n = n)
}

# ---- Moran local (LISA) con permutación condicional + corrección FDR (BH) ---
# La familia de pruebas para BH es el conjunto de países de UNA variable-año.
moran_local <- function(x, nb, nsim = 999L, alfa = 0.05) {
  stopifnot(!anyNA(x), length(x) == length(nb))
  n <- length(x)
  z <- x - mean(x)
  zs <- z / sqrt(mean(z^2))
  rezago <- vapply(nb, function(j) mean(zs[j]), numeric(1))
  Ii <- zs * rezago
  p <- vapply(seq_len(n), function(i) {
    ki <- length(nb[[i]])
    otros <- zs[-i]
    idx <- matrix(vapply(seq_len(nsim), function(s) sample.int(n - 1L, ki), integer(ki)),
                  nrow = ki)
    sim <- zs[i] * colMeans(matrix(otros[idx], nrow = ki))
    min(1, 2 * (min(sum(sim >= Ii[i]), sum(sim <= Ii[i])) + 1) / (nsim + 1))
  }, numeric(1))
  p_fdr <- stats::p.adjust(p, method = "BH")
  cuad <- dplyr::case_when(zs > 0 & rezago > 0 ~ "Alto-Alto",
                           zs < 0 & rezago < 0 ~ "Bajo-Bajo",
                           zs > 0 & rezago < 0 ~ "Alto-Bajo",
                           zs < 0 & rezago > 0 ~ "Bajo-Alto",
                           TRUE ~ NA_character_)
  tibble::tibble(valor = x, z = zs, rezago_z = rezago, Ii = Ii, p = p, p_fdr = p_fdr,
                 cuadrante = cuad,
                 grupo = dplyr::if_else(p_fdr < alfa & !is.na(cuad), cuad, "No significativo"))
}

# ---- Tema y mapas -------------------------------------------------------------
tema_mapa <- function(barra = TRUE) {
  t <- theme_dataquest(rejilla = "ninguna") +
    ggplot2::theme(axis.text = ggplot2::element_blank(),
                   axis.title = ggplot2::element_blank(),
                   axis.line = ggplot2::element_blank(),
                   axis.ticks = ggplot2::element_blank(),
                   legend.position = "bottom",
                   legend.justification = "left")
  if (barra) {
    t <- t + ggplot2::theme(legend.key.width = ggplot2::unit(3.2, "cm"),
                            legend.key.height = ggplot2::unit(0.35, "cm"))
  }
  t
}

# Mapa coroplético continuo. base: todas las fronteras (gris); datos: sf con la variable;
# resaltar: sf opcional (contorno de acento); facetas: nombre de columna o NULL.
mapa_coropletico <- function(base, datos, var, leyenda, titulo, subtitulo, caption,
                             resaltar = NULL, facetas = NULL, etiquetas = ggplot2::waiver()) {
  p <- ggplot2::ggplot() +
    ggplot2::geom_sf(data = base, fill = "grey88", colour = NA) +
    ggplot2::geom_sf(data = datos, ggplot2::aes(fill = .data[[var]]),
                     colour = "white", linewidth = 0.08)
  if (!is.null(resaltar)) {
    p <- p + ggplot2::geom_sf(data = resaltar, fill = NA, colour = PAL$acento, linewidth = 0.55)
  }
  if (!is.null(facetas)) p <- p + ggplot2::facet_wrap(facetas, ncol = 1)
  p +
    scale_fill_dq_c(name = leyenda, na.value = "grey88", labels = etiquetas) +
    ggplot2::coord_sf(datum = NA, expand = FALSE) +
    ggplot2::labs(title = titulo, subtitle = subtitulo, caption = caption) +
    tema_mapa(barra = TRUE)
}

# Mapa categórico (p. ej. grupos LISA). colores: vector nombrado.
mapa_categorico <- function(base, datos, var, colores, leyenda, titulo, subtitulo, caption,
                            resaltar = NULL, facetas = NULL) {
  p <- ggplot2::ggplot() +
    ggplot2::geom_sf(data = base, fill = "grey90", colour = NA) +
    ggplot2::geom_sf(data = datos, ggplot2::aes(fill = .data[[var]]),
                     colour = "white", linewidth = 0.08)
  if (!is.null(resaltar)) {
    p <- p + ggplot2::geom_sf(data = resaltar, fill = NA, colour = "black", linewidth = 0.5)
  }
  if (!is.null(facetas)) p <- p + ggplot2::facet_wrap(facetas, ncol = 1)
  p +
    ggplot2::scale_fill_manual(values = colores, name = leyenda, drop = FALSE) +
    ggplot2::coord_sf(datum = NA, expand = FALSE) +
    ggplot2::labs(title = titulo, subtitle = subtitulo, caption = caption) +
    tema_mapa(barra = FALSE)
}
