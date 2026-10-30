# ==============================================================================
# ASA DataQuest 2026 - WPP2024
# Script 05: Mapas coropléticos descriptivos (sin inferencia)
# ------------------------------------------------------------------------------
# Solo dibuja. La autocorrelación (Moran, LISA) está en el script 06.
# Los mapas usan las geometrías completas; no dependen de los puntos representativos.
#
# Entradas : data/clean/wpp_paises_medium_suppl.parquet, data/clean/mundo_geom.rds
# Salidas  : output/figuras/05_mapa_*.png
# Ejecutar de arriba hacia abajo, desde la raíz del proyecto.
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
suppressMessages(sf::sf_use_s2(TRUE))

ANIOS_MAPA <- c(2023L, 2050L, 2100L)
ETQ_ANIO <- c("2023" = "2023 · estimación", "2050" = "2050 · proyección Medium",
              "2100" = "2100 · proyección Medium")
CAP <- paste0("Fuente: UN World Population Prospects 2024 (Medium). Fronteras: Natural Earth 1:50m, ",
              "ilustrativas.\nColombia resaltada. Gris: sin dato o fuera del universo.")
CAP_U <- paste0("Fuente: UN WPP 2024 (Medium), proyección 2024-2100. Fronteras: Natural Earth, ilustrativas.\n",
                "Solo países con >= 1 millón de habitantes (los territorios pequeños dominarían el ranking).")

F_GEOM <- file.path(CFG$dir_clean, "mundo_geom.rds")
verificar(file.exists(F_GEOM), "Geometrías del script 04 encontradas.",
          "Faltan las geometrías: ejecuta primero scripts/04_espacial_geometrias.R")
mundo <- readRDS(F_GEOM)
amp <- amplitud_lon_partes(mundo)
verificar(max(amp$span) < 180,
          "Ningún polígono individual cruza el antimeridiano.",
          paste("Polígonos que cruzan el antimeridiano:", paste(unique(amp$iso3[amp$span >= 180]), collapse = ", "),
                "-> vuelve a ejecutar scripts/04_espacial_geometrias.R (D22)."))

con <- conectar_duckdb(if (exists("con")) con else NULL)
dbExecute(con, glue("CREATE OR REPLACE VIEW wpp AS
                     SELECT * FROM read_parquet('{file.path(CFG$dir_clean, CFG$f_parquet)}')"))


# ---- 1. Datos ----------------------------------------------------------------
datos_pais <- dbGetQuery(con, "
  SELECT ISO3_code AS iso3, Location, Time, MedianAgePop AS edad_mediana, TFR AS tfr,
         TPopulation1July AS pob_miles
  FROM wpp")
vel <- dbGetQuery(con, glue("
  WITH g AS (
    SELECT ISO3_code AS iso3, Time,
           MedianAgePop - LAG(MedianAgePop, 10) OVER (PARTITION BY ISO3_code ORDER BY Time) AS gan10
    FROM wpp)
  SELECT iso3, MAX(gan10) AS max_gan10, arg_max(Time, gan10) AS anio_max
  FROM g WHERE Time >= {CFG$ultimo_anio_estimado + 1}
  GROUP BY iso3"))
universo <- datos_pais |>
  filter(Time == CFG$ultimo_anio_estimado, pob_miles >= CFG$umbral_universo_miles) |> pull(iso3)
cat("Universo (>= 1 millón en 2023):", length(universo), "países;",
    sum(universo %in% mundo$iso3), "con polígono.\n")


# ---- 2. Mapas ----------------------------------------------------------------
seccion("2. MAPAS")

mundo_p <- tryCatch(sf::st_transform(mundo, CRS_MAPA),
                    error = function(e) sf::st_transform(mundo, "+proj=robin"))
col_p <- mundo_p |> filter(iso3 == "COL")

datos_anios <- datos_pais |> filter(Time %in% ANIOS_MAPA) |>
  mutate(panel = factor(ETQ_ANIO[as.character(Time)], levels = unname(ETQ_ANIO)))
m_anios <- inner_join(mundo_p, datos_anios, by = "iso3")

p1 <- mapa_coropletico(mundo_p, m_anios, "edad_mediana", "Edad mediana (años)",
                       "El envejecimiento avanza a ritmos distintos",
                       "Edad mediana de la población, 237 países y áreas.",
                       CAP, resaltar = col_p, facetas = "panel", etiquetas = fmt_num(1))
print(p1); guardar_fig(p1, "05_mapa_edad_mediana", ancho = 8, alto = 13.5)

p2 <- mapa_coropletico(mundo_p, m_anios, "tfr", "Hijos por mujer (TFR)",
                       "La fecundidad converge hacia el reemplazo o menos",
                       paste0("Nivel de reemplazo = ", format(CFG$tfr_reemplazo, decimal.mark = CFG$sep_decimal),
                              " hijos por mujer."),
                       CAP, resaltar = col_p, facetas = "panel", etiquetas = fmt_num(0.1))
print(p2); guardar_fig(p2, "05_mapa_tfr", ancho = 8, alto = 13.5)

m_vel <- inner_join(mundo_p, vel |> filter(iso3 %in% universo), by = "iso3")
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

cat("\nNota: Reunión, Guadalupe, Martinica, Mayotte y Guayana Francesa no tienen polígono propio;\n",
    "      en Natural Earth son parte de Francia y se ven con su color.\n", sep = "")

# dbDisconnect(con, shutdown = TRUE)