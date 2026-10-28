# ==============================================================================
# ASA DataQuest 2026 - WPP2024
# Script 05: Mapas, autocorrelación espacial global (Moran) y local (LISA)
# ------------------------------------------------------------------------------
# Implementa la sección 6.5 de PLAN_ANALITICO.md:
#   - Moran sobre variables CONTINUAS (no sobre etiquetas de clúster).
#   - Pesos por k vecinos más cercanos (hay islas sin vecinos por contigüidad).
#   - LISA con corrección FDR (Benjamini-Hochberg).
#   - Universo: países con >= 1 millón de habitantes en 2023 (D12).
# Todo es EXPLORATORIO (sección 7 del plan). Decisiones nuevas a registrar:
#   D22 fronteras y recodificaciones | D23 k = 5 con sensibilidad k = 3, 8
#   D24 FDR dentro de cada mapa (familia = países de una variable-año)
#
# Entradas : data/clean/wpp_paises_medium_suppl.parquet, mundo_geom.rds, mundo_puntos.rds
# Salidas  : output/figuras/05_*.png ; output/tablas/05_*.csv
# Ejecutar de arriba hacia abajo, desde la raíz del proyecto.
# ==============================================================================

# ---- 0. Entorno --------------------------------------------------------------
if (!file.exists("R/config.R")) stop("Abre el proyecto (.Rproj) o fija setwd() en la raíz.")
paquetes <- c("DBI", "duckdb", "dplyr", "tidyr", "glue", "tibble", "ggplot2", "scales", "sf")
faltan <- setdiff(paquetes, rownames(installed.packages()))
if (length(faltan) > 0) install.packages(faltan)
invisible(lapply(paquetes, library, character.only = TRUE))
source("R/config.R",           encoding = "UTF-8")
source("R/utils_datos.R",      encoding = "UTF-8")
source("R/tema.R",             encoding = "UTF-8")
source("R/utils_espacial.R",   encoding = "UTF-8")
crear_directorios()
set.seed(CFG$semilla)
suppressMessages(sf::sf_use_s2(TRUE))

NSIM       <- 999L                 # permutaciones (LISA y Moran en años clave)
NSIM_SERIE <- 199L                 # permutaciones por año en la serie 1950-2100
NSIM_LISA  <- 4999L                # LISA: piso del valor p = 2/(NSIM_LISA+1); con pocas permutaciones
# BH no puede declarar nada significativo (visto con k = 3)
K_BASE     <- 5L
K_SENS     <- c(3L, 5L, 8L)
ALFA       <- 0.05
ANIOS_MAPA <- c(2023L, 2050L, 2100L)
ETQ_ANIO <- c("2023" = "2023 · estimación", "2050" = "2050 · proyección Medium",
              "2100" = "2100 · proyección Medium")
CAP <- paste0("Fuente: UN World Population Prospects 2024 (Medium). Fronteras: Natural Earth 1:50m, ",
              "ilustrativas.\nColombia resaltada. Gris: sin dato o fuera del universo.")

F_GEOM <- file.path(CFG$dir_clean, "mundo_geom.rds")
F_PTS  <- file.path(CFG$dir_clean, "mundo_puntos.rds")
verificar(file.exists(F_GEOM) && file.exists(F_PTS), "Geometrías del script 04 encontradas.",
          "Faltan las geometrías: ejecuta primero scripts/04_espacial_geometrias.R")
mundo <- readRDS(F_GEOM)
pts   <- readRDS(F_PTS)
amp <- amplitud_lon_partes(mundo)
verificar(max(amp$span) < 180,
          "Ningún polígono cruza el antimeridiano: sin franjas horizontales en los mapas.",
          paste("Polígonos que cruzan el antimeridiano:", paste(unique(amp$iso3[amp$span >= 180]), collapse = ", "),
                "-> vuelve a ejecutar scripts/04_espacial_geometrias.R (D22)."))

con <- conectar_duckdb(if (exists("con")) con else NULL)
dbExecute(con, glue("CREATE OR REPLACE VIEW wpp AS
                     SELECT * FROM read_parquet('{file.path(CFG$dir_clean, CFG$f_parquet)}')"))


# ---- 1. Datos y universo -----------------------------------------------------
seccion("1. DATOS Y UNIVERSO")

datos_pais <- dbGetQuery(con, "
  SELECT ISO3_code AS iso3, Location, Time, MedianAgePop AS edad_mediana, TFR AS tfr,
         LEx AS lex, TPopulation1July AS pob_miles
  FROM wpp")

# Velocidad de envejecimiento: máxima ganancia de edad mediana en 10 años (proyección)
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
                 " países; faltan: ", paste(setdiff(universo, pts$iso3), collapse = ", ")),
          fatal = FALSE)
verificar("COL" %in% universo_esp, "Colombia está en el universo.", "Colombia no está en el universo.")

# Matrices país x año (filas en el orden de universo_esp)
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
cat("Vecinos más cercanos de Colombia (k = ", K_BASE, "):\n", sep = "")
ver(tibble(iso3 = universo_esp[nb5[[i_col]]]) |> left_join(nombres, by = "iso3"))
cat("Nota: los vecinos se calculan con el punto dentro del polígono más grande de cada país.\n",
    "      La relación es de cercanía, no de frontera común.\n", sep = "")


# ---- 3. Moran global ---------------------------------------------------------
seccion("3. MORAN GLOBAL")

combos <- bind_rows(lapply(names(MATS), function(v) tibble(variable = v, anio = ANIOS_MAPA)))
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
write.csv(tab_global, file.path(CFG$dir_tablas, "05_moran_global.csv"), row.names = FALSE)

# Verificación cruzada con spdep (si está instalado)
if (requireNamespace("spdep", quietly = TRUE)) {
  x_ref <- MATS$edad_mediana[, "2023"]
  I_spdep <- tryCatch(
    unname(spdep::moran.test(x_ref, spdep::nb2listw(nb5, style = "W"),
                             randomisation = TRUE)$estimate[1]),
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
  bind_rows(lapply(ANIOS_MAPA, function(a) {
    x <- MATS$edad_mediana[, as.character(a)]
    r <- moran_global(x, Wk, 499L)
    l <- moran_local(x, nbk, NSIM_LISA, ALFA)
    tibble(k = k, anio = a, I = round(r$I, 3), p_perm = r$p,
           n_lisa_significativos = sum(l$grupo != "No significativo"))
  }))
}))
ver(sens)
write.csv(sens, file.path(CFG$dir_tablas, "05_moran_sensibilidad_k.csv"), row.names = FALSE)


# ---- 5. Moran global año a año (1950-2100) -----------------------------------
seccion("5. MORAN GLOBAL POR AÑO")

serie_moran <- bind_rows(lapply(c("edad_mediana", "tfr"), function(v) {
  M <- MATS[[v]]
  bind_rows(lapply(colnames(M), function(a) {
    r <- moran_global(M[, a], W5, NSIM_SERIE)
    tibble(variable = v, anio = as.integer(a), I = r$I, p = r$p)
  }))
}))
write.csv(serie_moran, file.path(CFG$dir_tablas, "05_moran_serie.csv"), row.names = FALSE)
ver(serie_moran |> filter(anio %in% c(1950, 1975, 2000, 2023, 2050, 2075, 2100)) |>
      mutate(I = round(I, 3)))

serie_moran <- serie_moran |>
  mutate(etiqueta = factor(if_else(variable == "edad_mediana", "Edad mediana (años)",
                                   "Fecundidad (TFR, hijos por mujer)"),
                           levels = c("Edad mediana (años)", "Fecundidad (TFR, hijos por mujer)")))
p_ts <- ggplot(serie_moran, aes(anio, I)) +
  capa_proyeccion(etiquetas = FALSE) +
  geom_hline(yintercept = 0, colour = PAL$texto_suave, linewidth = 0.3) +
  geom_line(colour = PAL$estimacion, linewidth = 1.1, lineend = "round") +
  facet_wrap(~ etiqueta, ncol = 1, scales = "free_y") +
  scale_x_continuous(breaks = seq(1950, 2100, 25), expand = expansion(mult = c(0.01, 0.02))) +
  scale_y_continuous(labels = fmt_num(0.1)) +
  labs(title = "¿Se agrupan en el espacio los países parecidos?",
       subtitle = paste0("Índice de Moran global por año; universo de ", length(universo_esp),
                         " países, pesos fijos de ", K_BASE, " vecinos más cercanos.\n",
                         "Cero = sin patrón espacial. Zona sombreada = proyección (Medium): ",
                         "puede reflejar supuestos del modelo de la ONU."),
       x = NULL, y = "Moran I",
       caption = "Fuente: UN WPP 2024 (Medium). Análisis exploratorio.") +
  theme_dataquest()
print(p_ts)
guardar_fig(p_ts, "05_moran_serie_temporal", ancho = 9.5, alto = 7)


# ---- 6. LISA (Moran local) ---------------------------------------------------
seccion("6. LISA CON FDR (BH)")

lisa_lista <- lapply(ANIOS_MAPA, function(a) {
  r <- moran_local(MATS$edad_mediana[, as.character(a)], nb5, NSIM_LISA, ALFA)
  bind_cols(tibble(iso3 = universo_esp, variable = "edad_mediana", anio = a), r)
})
r_v <- moran_local(x_vel$max_gan10, nb5, NSIM_LISA, ALFA)
lisa <- bind_rows(lisa_lista,
                  bind_cols(tibble(iso3 = universo_esp, variable = "max_gan10_decada",
                                   anio = NA_integer_), r_v)) |>
  mutate(grupo = factor(grupo, levels = NIVELES_LISA)) |>
  left_join(nombres, by = "iso3")

cat("Valor p mínimo alcanzable con ", NSIM_LISA, " permutaciones: ", 2 / (NSIM_LISA + 1), "\n", sep = "")
cat("Conteo de grupos LISA por variable y año (BH dentro de cada familia, alfa = ", ALFA, "):\n", sep = "")
ver(lisa |> count(variable, anio, grupo) |> pivot_wider(names_from = grupo, values_from = n,
                                                        values_fill = 0L))
cat("\nColombia:\n")
ver(lisa |> filter(iso3 == "COL") |>
      transmute(variable, anio, valor = round(valor, 1), rezago_z = round(rezago_z, 2),
                p = round(p, 3), p_fdr = round(p_fdr, 3), grupo))
write.csv(lisa |> mutate(across(c(valor, z, rezago_z, Ii, p, p_fdr), ~ round(.x, 4))),
          file.path(CFG$dir_tablas, "05_lisa_resultados.csv"), row.names = FALSE)


# ---- 7. Mapas ----------------------------------------------------------------
seccion("7. MAPAS")

mundo_p <- tryCatch(sf::st_transform(mundo, CRS_MAPA),
                    error = function(e) sf::st_transform(mundo, "+proj=robin"))
col_p <- mundo_p |> filter(iso3 == "COL")

datos_anios <- datos_pais |> filter(Time %in% ANIOS_MAPA) |>
  mutate(panel = factor(ETQ_ANIO[as.character(Time)], levels = unname(ETQ_ANIO)))
m_anios <- inner_join(mundo_p, datos_anios, by = "iso3")

# 7.1 Edad mediana
p1 <- mapa_coropletico(mundo_p, m_anios, "edad_mediana", "Edad mediana (años)",
                       "El envejecimiento avanza, pero no al mismo ritmo en todo el mundo",
                       "Edad mediana de la población, 237 países y áreas.",
                       CAP, resaltar = col_p, facetas = "panel", etiquetas = fmt_num(1))
print(p1); guardar_fig(p1, "05_mapa_edad_mediana", ancho = 8, alto = 13.5)

# 7.2 Fecundidad
p2 <- mapa_coropletico(mundo_p, m_anios, "tfr", "Hijos por mujer (TFR)",
                       "La fecundidad converge hacia el nivel de reemplazo o por debajo",
                       paste0("Nivel de reemplazo = ", format(CFG$tfr_reemplazo, decimal.mark = CFG$sep_decimal),
                              " hijos por mujer."),
                       CAP, resaltar = col_p, facetas = "panel", etiquetas = fmt_num(0.1))
print(p2); guardar_fig(p2, "05_mapa_tfr", ancho = 8, alto = 13.5)

# 7.3 Velocidad de envejecimiento (solo universo) y año del máximo
m_vel <- inner_join(mundo_p, vel |> filter(iso3 %in% universo_esp), by = "iso3")
CAP_U <- paste0("Fuente: UN WPP 2024 (Medium), proyección 2024-2100. Fronteras: Natural Earth, ilustrativas.\n",
                "Solo países con >= 1 millón de habitantes (los territorios pequeños dominarían el ranking).")
p3 <- mapa_coropletico(mundo_p, m_vel, "max_gan10", "Años de edad mediana ganados en una década",
                       "Dónde se envejece más rápido",
                       "Máxima ganancia de edad mediana en 10 años dentro de 2024-2100.",
                       CAP_U, resaltar = col_p, etiquetas = fmt_num(0.1))
print(p3); guardar_fig(p3, "05_mapa_velocidad_envejecimiento", ancho = 9.5, alto = 5.8)

p4 <- mapa_coropletico(mundo_p, m_vel, "anio_max", "Año del máximo",
                       "Cuándo ocurre el envejecimiento más rápido",
                       "Año de la mayor ganancia de edad mediana en una década.",
                       CAP_U, resaltar = col_p,
                       etiquetas = scales::label_number(accuracy = 1, big.mark = ""))
print(p4); guardar_fig(p4, "05_mapa_anio_maximo_velocidad", ancho = 9.5, alto = 5.8)

# 7.4 LISA
COL_LISA <- c("Alto-Alto" = PAL$acento, "Bajo-Bajo" = PAL$okabe_ito[["azul"]],
              "Alto-Bajo" = PAL$okabe_ito[["naranja"]], "Bajo-Alto" = PAL$okabe_ito[["celeste"]],
              "No significativo" = "#B8BEC6")
CAP_L <- paste0("Fuente: UN WPP 2024 (Medium). LISA con ", NSIM_LISA, " permutaciones, ", K_BASE,
                " vecinos más cercanos y FDR (BH) = ", ALFA, " dentro de cada panel.\n",
                "Exploratorio. Contorno negro: Colombia. Gris claro: fuera del universo.")
lisa_edad <- lisa |> filter(variable == "edad_mediana") |>
  mutate(panel = factor(ETQ_ANIO[as.character(anio)], levels = unname(ETQ_ANIO)))
m_lisa <- inner_join(mundo_p, lisa_edad |> select(iso3, panel, grupo), by = "iso3")
p5 <- mapa_categorico(mundo_p, m_lisa, "grupo", COL_LISA, "Patrón local",
                      "Agrupaciones espaciales de la edad mediana",
                      "Alto-Alto: país con edad mediana alta rodeado de vecinos con edad alta (y análogo para las demás).",
                      CAP_L, resaltar = sf::st_cast(col_p, "MULTIPOLYGON"), facetas = "panel")
print(p5); guardar_fig(p5, "05_mapa_lisa_edad_mediana", ancho = 8, alto = 13.5)

m_lisa_v <- inner_join(mundo_p, lisa |> filter(variable == "max_gan10_decada") |> select(iso3, grupo),
                       by = "iso3")
p6 <- mapa_categorico(mundo_p, m_lisa_v, "grupo", COL_LISA, "Patrón local",
                      "Agrupaciones espaciales de la velocidad de envejecimiento",
                      "Máxima ganancia de edad mediana en una década (2024-2100).",
                      CAP_L, resaltar = sf::st_cast(col_p, "MULTIPOLYGON"))
print(p6); guardar_fig(p6, "05_mapa_lisa_velocidad", ancho = 9.5, alto = 5.8)


# ---- 8. Lectura y límites ----------------------------------------------------
seccion("8. LECTURA Y LÍMITES (para el reporte)")
cat(
  " - Unidad de análisis: país. Resultados dependen del tamaño y forma de las fronteras\n",
  "   (problema de la unidad de área modificable); por eso se reporta la sensibilidad a k.\n",
  " - 2023 es estimación; 2050 y 2100 son proyecciones. La ONU proyecta con modelos que\n",
  "   probablemente comparten información entre países: parte de la autocorrelación\n",
  "   proyectada puede venir del método (hipótesis, no verificada aquí).\n",
  " - LISA: BH dentro de cada mapa; no se ajusta entre mapas. Todo es exploratorio.\n",
  " - El resultado LISA es sensible a k (con k = 3 nada sale significativo tras BH; con k = 5 y 8 sí):\n",
  "   reportar siempre la tabla de sensibilidad. p = 0,002 en Moran global es el PISO con 999\n",
  "   permutaciones, no un valor estimado.\n",
  " - Moran alto (~0,7) refleja sobre todo gradientes continentales (África joven, Europa y Asia\n",
  "   oriental envejecidas); LISA localiza dónde, pero Colombia queda en 'No significativo'.\n",
  " - Reunión, Guadalupe, Martinica, Mayotte y Guayana Francesa no tienen polígono propio.\n",
  " - Los grupos describen patrones, no son etiquetas sobre los países (principio D6 de la ASA).\n",
  sep = "")

# dbDisconnect(con, shutdown = TRUE)