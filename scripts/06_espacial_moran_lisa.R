# ==============================================================================
# ASA DataQuest 2026 - WPP2024
# Script 06: Autocorrelación espacial (Moran global, serie temporal, LISA)
# ------------------------------------------------------------------------------
# Implementa la sección 6.5 de PLAN_ANALITICO.md. TODO es EXPLORATORIO.
#   - Moran sobre variables CONTINUAS (no sobre etiquetas de clúster).
#   - Pesos por k vecinos más cercanos (D23); permutaciones y FDR-BH (D24).
#   - Universo: países con >= 1 millón de habitantes en 2023 (D12).
#
# Entradas : data/clean/wpp_paises_medium_suppl.parquet, mundo_geom.rds, mundo_puntos.rds
# Salidas  : output/figuras/06_*.png ; output/tablas/06_*.csv
#            output/tablas/06_resumen_corrida.md  <- bloque listo para pegar en
#                                                    ANALISIS_ESPACIAL.md (registro de corridas)
# Ejecutar de arriba hacia abajo, desde la raíz del proyecto (el 04 debe estar al día).
# ==============================================================================

# ---- 0. Entorno --------------------------------------------------------------
if (!file.exists("R/config.R")) stop("Abre el proyecto (.Rproj) o fija setwd() en la raíz.")
paquetes <- c("DBI", "duckdb", "dplyr", "tidyr", "glue", "tibble", "ggplot2", "scales", "sf")
faltan <- setdiff(paquetes, rownames(installed.packages()))
if (length(faltan) > 0) install.packages(faltan)
invisible(lapply(paquetes, library, character.only = TRUE))
source("R/config.R",         encoding = "UTF-8")
source("R/utils_datos.R",    encoding = "UTF-8")
source("R/tema.R",           encoding = "UTF-8")
source("R/utils_espacial.R", encoding = "UTF-8")
crear_directorios()
set.seed(CFG$semilla)
suppressMessages(sf::sf_use_s2(TRUE))

NSIM       <- 999L       # permutaciones del Moran global (piso del valor p = 2/(NSIM+1))
NSIM_SERIE <- 199L       # permutaciones por año en la serie 1950-2100
NSIM_LISA  <- 4999L      # permutaciones del LISA (piso del valor p = 2/(NSIM_LISA+1))
K_BASE     <- 5L
K_SENS     <- c(3L, 5L, 8L)
ALFA       <- 0.05
ANIOS_CLAVE <- c(2023L, 2050L, 2100L)
ETQ_ANIO <- c("2023" = "2023 · estimación", "2050" = "2050 · proyección Medium",
              "2100" = "2100 · proyección Medium")
COL_LISA <- c("Alto-Alto" = PAL$acento, "Bajo-Bajo" = PAL$okabe_ito[["azul"]],
              "Alto-Bajo" = PAL$okabe_ito[["naranja"]], "Bajo-Alto" = PAL$okabe_ito[["celeste"]],
              "No significativo" = "#B8BEC6")

F_GEOM <- file.path(CFG$dir_clean, "mundo_geom.rds")
F_PTS  <- file.path(CFG$dir_clean, "mundo_puntos.rds")
verificar(file.exists(F_GEOM) && file.exists(F_PTS), "Geometrías del script 04 encontradas.",
          "Faltan las geometrías: ejecuta primero scripts/04_espacial_geometrias.R")
mundo <- readRDS(F_GEOM)
pts   <- readRDS(F_PTS)

# Controles de las geometrías (el error de a_partes() afectaba a los puntos, D22)
amp <- amplitud_lon_partes(mundo)
verificar(max(amp$span) < 180, "Ningún polígono individual cruza el antimeridiano.",
          paste("Polígonos que cruzan el antimeridiano:", paste(unique(amp$iso3[amp$span >= 180]), collapse = ", "),
                "-> vuelve a ejecutar scripts/04_espacial_geometrias.R."))
verificar(punto_en_caja(pts, "FRA", c(-5, 8.5), c(42, 51.5)) && punto_en_caja(pts, "USA", c(-125, -66), c(24, 50)),
          "Puntos de Francia y Estados Unidos dentro de su territorio continental.",
          "Los puntos de Francia o EE. UU. están mal: vuelve a ejecutar el 04 corregido (a_partes).")

con <- conectar_duckdb(if (exists("con")) con else NULL)
dbExecute(con, glue("CREATE OR REPLACE VIEW wpp AS
                     SELECT * FROM read_parquet('{file.path(CFG$dir_clean, CFG$f_parquet)}')"))


# ---- 1. Datos y universo -----------------------------------------------------
seccion("1. DATOS Y UNIVERSO")

datos_pais <- dbGetQuery(con, "
  SELECT ISO3_code AS iso3, Location, Time, MedianAgePop AS edad_mediana, TFR AS tfr,
         LEx AS lex, TPopulation1July AS pob_miles
  FROM wpp")
vel <- dbGetQuery(con, glue("
  WITH g AS (
    SELECT ISO3_code AS iso3, Time,
           MedianAgePop - LAG(MedianAgePop, 10) OVER (PARTITION BY ISO3_code ORDER BY Time) AS gan10
    FROM wpp)
  SELECT iso3, MAX(gan10) AS max_gan10, arg_max(Time, gan10) AS anio_max
  FROM g WHERE Time >= {CFG$ultimo_anio_estimado + 1}
  GROUP BY iso3"))

nombres <- datos_pais |> filter(Time == CFG$ultimo_anio_estimado) |> select(iso3, Location)
universo <- datos_pais |>
  filter(Time == CFG$ultimo_anio_estimado, pob_miles >= CFG$umbral_universo_miles) |> pull(iso3)
universo_esp <- sort(intersect(universo, pts$iso3))
verificar(length(universo_esp) == length(universo),
          paste0("Universo espacial: ", length(universo_esp), " países (todos con polígono)."),
          paste0("Universo espacial: ", length(universo_esp), " de ", length(universo),
                 " países; faltan: ", paste(setdiff(universo, pts$iso3), collapse = ", ")), fatal = FALSE)
verificar("COL" %in% universo_esp, "Colombia está en el universo.", "Colombia no está en el universo.")

matriz_anio <- function(var) {
  w <- datos_pais |> filter(iso3 %in% universo_esp) |>
    select(iso3, Time, valor = all_of(var)) |>
    pivot_wider(names_from = Time, values_from = valor) |>
    arrange(match(iso3, universo_esp))
  stopifnot(identical(w$iso3, universo_esp))
  m <- as.matrix(select(w, -iso3))
  rownames(m) <- w$iso3
  m <- m[, as.character(sort(as.integer(colnames(m)))), drop = FALSE]
  stopifnot(!anyNA(m))
  m
}
MATS <- list(edad_mediana = matriz_anio("edad_mediana"), tfr = matriz_anio("tfr"),
             lex = matriz_anio("lex"))
x_vel <- vel |> filter(iso3 %in% universo_esp) |> arrange(match(iso3, universo_esp))
stopifnot(identical(x_vel$iso3, universo_esp), !anyNA(x_vel$max_gan10))


# ---- 2. Pesos espaciales (kNN) -----------------------------------------------
seccion("2. PESOS ESPACIALES: k VECINOS MÁS CERCANOS")

pts_u <- pts[match(universo_esp, pts$iso3), ]
nb5 <- vecinos_knn(pts_u, K_BASE)
W5  <- matriz_w(nb5)

i_col <- match("COL", universo_esp)
vec_col <- tibble(iso3 = universo_esp[nb5[[i_col]]]) |> left_join(nombres, by = "iso3")
cat("Vecinos más cercanos de Colombia (k = ", K_BASE, "):\n", sep = "")
ver(vec_col)
cat("Los vecinos se calculan con un punto dentro del polígono más grande de cada país:\n",
    "es cercanía, no frontera común.\n", sep = "")


# ---- 3. Moran global ---------------------------------------------------------
seccion("3. MORAN GLOBAL")

combos <- bind_rows(lapply(names(MATS), function(v) tibble(variable = v, anio = ANIOS_CLAVE)))
tab_global <- bind_rows(lapply(seq_len(nrow(combos)), function(i) {
  v <- combos$variable[i]; a <- combos$anio[i]
  r <- moran_global(MATS[[v]][, as.character(a)], W5, NSIM)
  tibble(variable = v, anio = a, n = r$n, I = r$I, esperado = r$esperado, p_perm = r$p)
}))
r_vel <- moran_global(x_vel$max_gan10, W5, NSIM)
tab_global <- bind_rows(tab_global,
                        tibble(variable = "max_gan10_decada", anio = NA_integer_, n = r_vel$n,
                               I = r_vel$I, esperado = r_vel$esperado, p_perm = r_vel$p)) |>
  mutate(tipo = case_when(is.na(anio) ~ "proyección", anio <= CFG$ultimo_anio_estimado ~ "estimación",
                          TRUE ~ "proyección"),
         across(c(I, esperado), ~ round(.x, 3)))
ver(tab_global)
cat("Valor p mínimo alcanzable con ", NSIM, " permutaciones: ", 2 / (NSIM + 1), "\n", sep = "")
write.csv(tab_global, file.path(CFG$dir_tablas, "06_moran_global.csv"), row.names = FALSE)

if (requireNamespace("spdep", quietly = TRUE)) {
  x_ref <- MATS$edad_mediana[, "2023"]
  I_spdep <- tryCatch(
    unname(spdep::moran.test(x_ref, spdep::nb2listw(nb5, style = "W"), randomisation = TRUE)$estimate[1]),
    error = function(e) NA_real_)
  I_mio <- moran_global(x_ref, W5, 0L)$I
  verificar(isTRUE(abs(I_spdep - I_mio) < 1e-8),
            sprintf("Moran propio = spdep::moran.test (I = %.4f).", I_mio),
            "No se pudo confirmar el Moran propio contra spdep (error o diferencia).", fatal = FALSE)
} else {
  cat("  (spdep no está instalado: se omite la verificación cruzada.)\n")
}


# ---- 4. Sensibilidad al número de vecinos ------------------------------------
seccion("4. SENSIBILIDAD A k (edad mediana)")

sens <- bind_rows(lapply(K_SENS, function(k) {
  nbk <- vecinos_knn(pts_u, k); Wk <- matriz_w(nbk)
  bind_rows(lapply(ANIOS_CLAVE, function(a) {
    x <- MATS$edad_mediana[, as.character(a)]
    r <- moran_global(x, Wk, 499L)
    l <- moran_local(x, nbk, NSIM_LISA, ALFA, semilla = CFG$semilla)
    tibble(k = k, anio = a, I = round(r$I, 3), p_perm = r$p,
           n_lisa_significativos = sum(l$grupo != "No significativo"))
  }))
}))
ver(sens)
write.csv(sens, file.path(CFG$dir_tablas, "06_moran_sensibilidad_k.csv"), row.names = FALSE)

# 4b. Estabilidad Monte Carlo: el conteo de LISA significativos depende de las permutaciones
# aleatorias (BH amplifica diferencias pequeñas de p cerca del umbral). Se repite con 3 semillas.
seccion("4b. ESTABILIDAD MONTE CARLO DEL CONTEO LISA (k = 5)")
SEMILLAS_MC <- CFG$semilla + 1:3
estab <- bind_rows(lapply(ANIOS_CLAVE, function(a) {
  x <- MATS$edad_mediana[, as.character(a)]
  n_sig <- vapply(SEMILLAS_MC, function(s) {
    sum(moran_local(x, nb5, NSIM_LISA, ALFA, semilla = s)$grupo != "No significativo")
  }, numeric(1))
  tibble(anio = a, semillas = length(SEMILLAS_MC), minimo = min(n_sig), maximo = max(n_sig))
}))
ver(estab)
write.csv(estab, file.path(CFG$dir_tablas, "06_lisa_estabilidad_montecarlo.csv"), row.names = FALSE)
cat("Si minimo y maximo difieren mucho, el conteo se reporta como rango y no como cifra puntual.\n")


# ---- 5. LISA (Moran local) ---------------------------------------------------
seccion("5. LISA CON FDR (BH)")

lisa_lista <- lapply(ANIOS_CLAVE, function(a) {
  r <- moran_local(MATS$edad_mediana[, as.character(a)], nb5, NSIM_LISA, ALFA, semilla = CFG$semilla)
  bind_cols(tibble(iso3 = universo_esp, variable = "edad_mediana", anio = a), r)
})
r_v <- moran_local(x_vel$max_gan10, nb5, NSIM_LISA, ALFA, semilla = CFG$semilla)
lisa <- bind_rows(lisa_lista,
                  bind_cols(tibble(iso3 = universo_esp, variable = "max_gan10_decada",
                                   anio = NA_integer_), r_v)) |>
  mutate(grupo = factor(grupo, levels = NIVELES_LISA)) |>
  left_join(nombres, by = "iso3")

cat("Valor p mínimo alcanzable con ", NSIM_LISA, " permutaciones: ", 2 / (NSIM_LISA + 1), "\n", sep = "")
cat("Conteo de grupos LISA (BH dentro de cada familia, alfa = ", ALFA, "):\n", sep = "")
lisa_conteos <- lisa |> count(variable, anio, grupo) |>
  pivot_wider(names_from = grupo, values_from = n, values_fill = 0L) |>
  select(variable, anio, any_of(NIVELES_LISA))
ver(lisa_conteos)

cat("\nColombia:\n")
tab_col <- lisa |> filter(iso3 == "COL") |>
  transmute(variable, anio, valor = round(valor, 1), rezago_z = round(rezago_z, 2),
            p = round(p, 3), p_fdr = round(p_fdr, 3), grupo)
ver(tab_col)

# Transiciones de grupo LISA de la edad mediana entre 2023, 2050 y 2100
tr <- lisa |> filter(variable == "edad_mediana") |> select(iso3, Location, anio, grupo) |>
  pivot_wider(names_from = anio, values_from = grupo, names_prefix = "g")
tab_trans <- tr |> count(g2023, g2100, name = "paises")
cat("\nGrupo LISA en 2023 (filas) frente a 2100 (columnas), número de países:\n")
ver(tab_trans)
cat("\nPaíses con patrón significativo en 2023 y 'No significativo' en 2100:\n")
ver(tr |> filter(g2023 %in% c("Alto-Alto", "Bajo-Bajo"), g2100 == "No significativo") |>
      arrange(g2023, Location) |> select(Location, g2023, g2050, g2100))

write.csv(lisa |> mutate(across(c(valor, z, rezago_z, Ii, p, p_fdr), ~ round(.x, 4))),
          file.path(CFG$dir_tablas, "06_lisa_resultados.csv"), row.names = FALSE)
write.csv(tab_trans, file.path(CFG$dir_tablas, "06_lisa_transiciones_2023_2100.csv"), row.names = FALSE)


# ---- 6. Moran global año a año (1950-2100) -----------------------------------
seccion("6. MORAN GLOBAL POR AÑO")

serie_moran <- bind_rows(lapply(names(MATS), function(v) {
  M <- MATS[[v]]
  bind_rows(lapply(colnames(M), function(a) {
    r <- moran_global(M[, a], W5, NSIM_SERIE)
    tibble(variable = v, anio = as.integer(a), I = r$I, p = r$p)
  }))
}))
write.csv(serie_moran, file.path(CFG$dir_tablas, "06_moran_serie.csv"), row.names = FALSE)
serie_clave <- serie_moran |> filter(anio %in% c(1950, 1975, 2000, 2023, 2050, 2075, 2100)) |>
  mutate(I = round(I, 3)) |> select(-p) |> pivot_wider(names_from = variable, values_from = I)
ver(serie_clave)


# ---- 7. Figuras --------------------------------------------------------------
seccion("7. FIGURAS")

# 7.1 Diagrama de dispersión de Moran (pendiente de la recta = Moran I)
sc <- lisa |> filter(variable == "edad_mediana") |>
  mutate(panel = factor(ETQ_ANIO[as.character(anio)], levels = unname(ETQ_ANIO)))
p_sc <- ggplot(sc, aes(z, rezago_z)) +
  geom_hline(yintercept = 0, colour = PAL$texto_suave, linewidth = 0.3) +
  geom_vline(xintercept = 0, colour = PAL$texto_suave, linewidth = 0.3) +
  geom_smooth(method = "lm", formula = y ~ x, se = FALSE, colour = PAL$texto_suave, linewidth = 0.7) +
  geom_point(aes(colour = grupo), size = 1.9, alpha = 0.85) +
  geom_point(data = filter(sc, iso3 == "COL"), shape = 21, size = 3.6, stroke = 1.2,
             fill = NA, colour = "black") +
  geom_text(data = filter(sc, iso3 == "COL"), label = "Colombia", nudge_y = 0.28,
            size = 3.2, fontface = "bold") +
  facet_wrap(~ panel, nrow = 1) +
  scale_colour_manual(values = COL_LISA, name = NULL, drop = FALSE) +
  scale_x_continuous(labels = fmt_num(0.1)) + scale_y_continuous(labels = fmt_num(0.1)) +
  labs(title = "Los países con edad mediana alta tienen vecinos con edad mediana alta",
       subtitle = paste0("Edad mediana estandarizada (eje x) frente al promedio de sus ", K_BASE,
                         " vecinos más cercanos (eje y). La pendiente de la recta es el Moran I."),
       x = "Edad mediana del país (desviaciones estándar)",
       y = "Promedio de los vecinos (desv. est.)",
       caption = paste0("Fuente: UN WPP 2024 (Medium). ", length(universo_esp),
                        " países con >= 1 millón de habitantes. Color: grupo LISA con FDR (BH) ", ALFA, ".")) +
  theme_dataquest(rejilla = "xy") + theme(legend.position = "bottom")
print(p_sc); guardar_fig(p_sc, "06_moran_dispersion", ancho = 11, alto = 4.8)

# 7.2 Serie temporal del Moran global
serie_moran <- serie_moran |>
  mutate(etiqueta = factor(recode(variable, edad_mediana = "Edad mediana (años)",
                                  tfr = "Fecundidad (TFR, hijos por mujer)",
                                  lex = "Esperanza de vida al nacer (años)"),
                           levels = c("Edad mediana (años)", "Fecundidad (TFR, hijos por mujer)",
                                      "Esperanza de vida al nacer (años)")))
p_ts <- ggplot(serie_moran, aes(anio, I)) +
  capa_proyeccion(etiquetas = FALSE) +
  geom_hline(yintercept = 0, colour = PAL$texto_suave, linewidth = 0.3) +
  geom_line(colour = PAL$estimacion, linewidth = 1.1, lineend = "round") +
  facet_wrap(~ etiqueta, ncol = 1, scales = "free_y") +
  scale_x_continuous(breaks = seq(1950, 2100, 25), expand = expansion(mult = c(0.01, 0.02))) +
  scale_y_continuous(labels = fmt_num(0.1)) +
  labs(title = "¿Se agrupan en el espacio los países parecidos?",
       subtitle = paste0("Índice de Moran global por año; ", length(universo_esp), " países, pesos fijos de ",
                         K_BASE, " vecinos más cercanos.\n",
                         "Cero = sin patrón espacial. Zona sombreada = proyección (Medium): ",
                         "puede reflejar supuestos del modelo de la ONU."),
       x = NULL, y = "Moran I", caption = "Fuente: UN WPP 2024 (Medium). Análisis exploratorio.") +
  theme_dataquest()
print(p_ts); guardar_fig(p_ts, "06_moran_serie_temporal", ancho = 9.5, alto = 9)

# 7.3 Mapas LISA
mundo_p <- tryCatch(sf::st_transform(mundo, CRS_MAPA),
                    error = function(e) sf::st_transform(mundo, "+proj=robin"))
col_p <- mundo_p |> filter(iso3 == "COL")
CAP_L <- paste0("Fuente: UN WPP 2024 (Medium). LISA con ", NSIM_LISA, " permutaciones, ", K_BASE,
                " vecinos más cercanos y FDR (BH) = ", ALFA, " dentro de cada panel.\n",
                "Exploratorio. Contorno negro: Colombia. Gris claro: fuera del universo.")

m_lisa <- inner_join(mundo_p, sc |> select(iso3, panel, grupo), by = "iso3")
p5 <- mapa_categorico(mundo_p, m_lisa, "grupo", COL_LISA, "Patrón local",
                      "Agrupaciones espaciales de la edad mediana",
                      "Alto-Alto: país con edad mediana alta rodeado de vecinos con edad alta (y análogo para las demás).",
                      CAP_L, resaltar = col_p, facetas = "panel")
print(p5); guardar_fig(p5, "06_mapa_lisa_edad_mediana", ancho = 8, alto = 13.5)

m_lisa_v <- inner_join(mundo_p, lisa |> filter(variable == "max_gan10_decada") |> select(iso3, grupo), by = "iso3")
p6 <- mapa_categorico(mundo_p, m_lisa_v, "grupo", COL_LISA, "Patrón local",
                      "Agrupaciones espaciales de la velocidad de envejecimiento",
                      "Máxima ganancia de edad mediana en una década (2024-2100).",
                      CAP_L, resaltar = col_p)
print(p6); guardar_fig(p6, "06_mapa_lisa_velocidad", ancho = 9.5, alto = 5.8)


# ---- 8. Resumen de la corrida en Markdown ------------------------------------
seccion("8. RESUMEN DE LA CORRIDA (para ANALISIS_ESPACIAL.md)")

f_md <- file.path(CFG$dir_tablas, "06_resumen_corrida.md")
res <- c(
  paste0("### Corrida del ", format(Sys.time(), "%Y-%m-%d %H:%M")), "",
  paste0("- Universo espacial: ", length(universo_esp), " países; k = ", K_BASE, "; semilla ", CFG$semilla, "."),
  paste0("- Permutaciones: Moran global ", NSIM, ", serie ", NSIM_SERIE, ", LISA ", NSIM_LISA, "."),
  paste0("- Vecinos más cercanos de Colombia: ", paste(vec_col$Location, collapse = ", "), "."), "",
  "**Moran global** (p = piso con las permutaciones usadas, no un valor estimado):", "",
  md_tabla(tab_global), "",
  "**Sensibilidad a k** (edad mediana; LISA significativos tras FDR):", "",
  md_tabla(sens), "",
  "**Estabilidad Monte Carlo del conteo LISA** (k = 5, 3 semillas):", "",
  md_tabla(estab), "",
  "**Grupos LISA** (BH dentro de cada variable-año):", "",
  md_tabla(lisa_conteos), "",
  "**Colombia:**", "",
  md_tabla(tab_col), "",
  "**Grupo LISA de la edad mediana, 2023 frente a 2100** (países):", "",
  md_tabla(tab_trans), "",
  "**Moran global por año** (años clave):", "",
  md_tabla(serie_clave), "")
writeLines(enc2utf8(res), f_md, useBytes = TRUE)
cat("Resumen guardado en:", f_md, "\n",
    "Pega su contenido en ANALISIS_ESPACIAL.md (sección 'Registro de corridas').\n", sep = "")

cat("\nLectura y límites:\n",
    " - Unidad de análisis: país; los resultados dependen del tamaño y forma de las fronteras (MAUP).\n",
    " - 2023 es estimación; 2050 y 2100 son proyecciones, y el modelo de la ONU puede inducir parte del patrón.\n",
    " - El conteo LISA es sensible a k y al azar de las permutaciones: reportar rango y tabla de sensibilidad.\n",
    " - BH se aplica dentro de cada mapa, no entre mapas. Todo es exploratorio.\n",
    " - Los grupos describen patrones, no son etiquetas sobre los países (principio D6 de la ASA).\n", sep = "")

# dbDisconnect(con, shutdown = TRUE)