# ==============================================================================
# ASA DataQuest 2026 - WPP2024
# Script 02: Universo de análisis, bandas oficiales (PI) y efecto de la migración
# ------------------------------------------------------------------------------
# Responde tres preguntas ANTES de modelar (ver PLAN_ANALITICO.md):
#   1. ¿Con qué umbral de población se define el universo de análisis? (D12)
#   2. ¿Las etiquetas Lower/Upper de los intervalos siguen el orden numérico del
#      indicador, o hay que construir la banda como [mínimo, máximo]? (D14)
#   3. ¿Cuánto cambia la edad mediana al eliminar la migración, en TODOS los
#      países y no solo en Colombia? (D17)
# Entradas : data/clean/wpp_paises_medium_suppl.parquet, OtherVariants (raw)
# Salidas  : output/tablas/02_*.csv ; data/raw/externos/FUENTES.md (plantilla)
# Ejecutar de arriba hacia abajo, desde la raíz del proyecto.
# ==============================================================================

# ---- 0. Entorno --------------------------------------------------------------
if (!file.exists("R/config.R")) stop("Abre el proyecto (.Rproj) o fija setwd() en la raíz.")
paquetes <- c("DBI", "duckdb", "dplyr", "tidyr", "glue", "tibble")
invisible(lapply(paquetes, library, character.only = TRUE))
source("R/config.R",      encoding = "UTF-8")
source("R/utils_datos.R", encoding = "UTF-8")
crear_directorios()

con <- conectar_duckdb(if (exists("con")) con else NULL)
ruta_parquet <- file.path(CFG$dir_clean, CFG$f_parquet)
dbExecute(con, glue("CREATE OR REPLACE VIEW wpp AS
                     SELECT * FROM read_parquet('{ruta_parquet}')"))
crear_vista_csv(con, "other_raw", CFG$f_other)

PAIS <- "COL"
UMBRAL_POB_MILES <- 1000   # 1 millón de habitantes (TPopulation1Jan está en miles)


# ---- 1. Universo de análisis (D12) -------------------------------------------
seccion("1. UNIVERSO DE ANÁLISIS POR UMBRAL DE POBLACIÓN (2023)")

pob23 <- dbGetQuery(con, glue("
  SELECT ISO3_code, Location, TPopulation1July AS pob_miles
  FROM wpp WHERE Time = {CFG$ultimo_anio_estimado}"))

tabla_umbral <- tibble(umbral_miles = c(0, 100, 500, 1000, 2000, 5000)) |>
  rowwise() |>
  mutate(n_paises = sum(pob23$pob_miles >= umbral_miles),
         pct_poblacion_mundial = round(100 * sum(pob23$pob_miles[pob23$pob_miles >= umbral_miles]) /
                                         sum(pob23$pob_miles), 2)) |>
  ungroup()
ver(tabla_umbral)

excluidos <- pob23 |> filter(pob_miles < UMBRAL_POB_MILES) |> arrange(desc(pob_miles))
cat(sprintf("\nCon umbral = %s miles: quedan %d países; se excluyen %d (%.2f %% de la población).\n",
            format(UMBRAL_POB_MILES, big.mark = ","),
            sum(pob23$pob_miles >= UMBRAL_POB_MILES), nrow(excluidos),
            100 * sum(excluidos$pob_miles) / sum(pob23$pob_miles)))
cat("Excluidos de mayor tamaño:\n"); ver(head(excluidos, 15))

dbExecute(con, glue("
  CREATE OR REPLACE VIEW universo AS
  SELECT ISO3_code FROM wpp
  WHERE Time = {CFG$ultimo_anio_estimado} AND TPopulation1July >= {UMBRAL_POB_MILES}"))

# Ranking de velocidad de envejecimiento DENTRO del universo
rank_vel <- dbGetQuery(con, glue("
  WITH g AS (
    SELECT ISO3_code, Location, Time,
           MedianAgePop - LAG(MedianAgePop, 10) OVER (PARTITION BY ISO3_code ORDER BY Time) AS gan10
    FROM wpp),
  m AS (
    SELECT ISO3_code, Location, MAX(gan10) AS max_gan10, arg_max(Time, gan10) AS anio_max
    FROM g
    WHERE Time >= {CFG$ultimo_anio_estimado + 1} AND ISO3_code IN (SELECT ISO3_code FROM universo)
    GROUP BY 1, 2)
  SELECT RANK() OVER (ORDER BY max_gan10 DESC) AS posicion,
         ISO3_code, Location, ROUND(max_gan10, 1) AS max_ganancia_10a, anio_max
  FROM m ORDER BY posicion"))
cat("\nPaíses con mayor velocidad de envejecimiento (universo):\n"); ver(head(rank_vel, 15))
cat(sprintf("\nPosición de %s: ", PAIS)); ver(filter(rank_vel, ISO3_code == PAIS))


# ---- 2. ¿Las etiquetas Lower/Upper siguen el orden numérico? (D14) -----------
seccion("2. ORDEN DE LAS BANDAS OFICIALES (Lower 80 PI vs Upper 80 PI)")

orden_pi <- dbGetQuery(con, glue("
  WITH l AS (
    SELECT LocID, Time, TFR AS tfr, LEx AS lex, MedianAgePop AS edad, TPopulation1July AS pob
    FROM other_raw WHERE Variant = 'Lower 80 PI' AND {SQL_ES_PAIS} AND Time IN (2050, 2100)),
  u AS (
    SELECT LocID, Time, TFR AS tfr, LEx AS lex, MedianAgePop AS edad, TPopulation1July AS pob
    FROM other_raw WHERE Variant = 'Upper 80 PI' AND {SQL_ES_PAIS} AND Time IN (2050, 2100))
  SELECT l.Time, COUNT(*) AS paises,
         ROUND(AVG(CASE WHEN l.tfr  < u.tfr  THEN 1.0 ELSE 0 END), 3) AS prop_lower_menor_tfr,
         ROUND(AVG(CASE WHEN l.lex  < u.lex  THEN 1.0 ELSE 0 END), 3) AS prop_lower_menor_lex,
         ROUND(AVG(CASE WHEN l.edad < u.edad THEN 1.0 ELSE 0 END), 3) AS prop_lower_menor_edad,
         ROUND(AVG(CASE WHEN l.pob  < u.pob  THEN 1.0 ELSE 0 END), 3) AS prop_lower_menor_pob
  FROM l JOIN u USING (LocID, Time) GROUP BY l.Time ORDER BY l.Time"))
ver(orden_pi)
cat("\nLectura: si prop_lower_menor_* ~ 1, 'Lower' es numéricamente menor (orden normal).\n",
    "Si ~ 0, la etiqueta está invertida para ese indicador. Valores intermedios\n",
    "indican mezcla: en ese caso la banda DEBE construirse como [mínimo, máximo] del par.\n", sep = "")

# ¿Medium cae siempre dentro de [min, max] del par 80 %? (comprobación de la regla)
dentro <- dbGetQuery(con, glue("
  WITH b AS (
    SELECT l.LocID, l.Time,
           LEAST(l.MedianAgePop, u.MedianAgePop)    AS lo,
           GREATEST(l.MedianAgePop, u.MedianAgePop) AS hi
    FROM other_raw l JOIN other_raw u ON l.LocID = u.LocID AND l.Time = u.Time
    WHERE l.Variant = 'Lower 80 PI' AND u.Variant = 'Upper 80 PI'
      AND l.Time BETWEEN {CFG$ultimo_anio_estimado + 1} AND {CFG$ultimo_anio_analisis}
      AND l.ISO3_code IS NOT NULL AND TRIM(l.ISO3_code) <> '')
  SELECT COUNT(*) AS n,
         ROUND(AVG(CASE WHEN m.MedianAgePop BETWEEN b.lo AND b.hi THEN 1.0 ELSE 0 END), 4) AS prop_medium_dentro
  FROM b JOIN wpp m ON m.LocID = b.LocID AND m.Time = b.Time"))
cat("\nProporción de país-año donde Medium cae dentro de la banda [min, max] del 80 %:\n"); ver(dentro)


# ---- 3. Efecto de la migración sobre la edad mediana (D17) -------------------
seccion("3. EFECTO DE LA MIGRACIÓN: 'Zero migration' - 'Medium' (edad mediana)")

mig <- dbGetQuery(con, "
  SELECT o.Time, o.ISO3_code, o.Location, o.MedianAgePop - m.MedianAgePop AS dif_edad
  FROM other_raw o JOIN wpp m ON o.LocID = m.LocID AND o.Time = m.Time
  WHERE o.Variant = 'Zero migration' AND o.Time IN (2050, 2100)
    AND o.ISO3_code IN (SELECT ISO3_code FROM universo)")

resumen_mig <- mig |>
  group_by(Time) |>
  summarise(paises = n(),
            min = round(min(dif_edad), 2),
            p10 = round(quantile(dif_edad, 0.10), 2),
            mediana = round(median(dif_edad), 2),
            p90 = round(quantile(dif_edad, 0.90), 2),
            max = round(max(dif_edad), 2),
            n_abs_mayor_2a = sum(abs(dif_edad) > 2), .groups = "drop")
ver(resumen_mig)

cat("\nPaíses donde la migración más cambia la edad mediana en 2100 (|dif| mayor):\n")
ver(mig |> filter(Time == 2100) |> arrange(desc(abs(dif_edad))) |> head(10) |>
      mutate(dif_edad = round(dif_edad, 2)))
cat(sprintf("\n%s: ", PAIS)); ver(mig |> filter(ISO3_code == PAIS) |> mutate(dif_edad = round(dif_edad, 2)))


# ---- 4. Registro de datos externos (D13) -------------------------------------
seccion("4. REGISTRO DE DATOS EXTERNOS")

dir_ext <- file.path(CFG$dir_raw, "externos")
dir.create(dir_ext, showWarnings = FALSE, recursive = TRUE)
f_registro <- file.path(dir_ext, "FUENTES.md")

if (!file.exists(f_registro)) {
  writeLines(c(
    "# Registro de fuentes externas",
    "",
    "Regla: ninguna fuente externa se usa sin una entrada completa en esta tabla.",
    "",
    "| ID | Fuente | URL | Archivo local | Fecha de descarga | Licencia | Transformaciones | Estado |",
    "|---|---|---|---|---|---|---|---|",
    "| E1 | ONU WPP 2024 - población por edad simple y sexo (Medium/Low/High) | https://population.un.org/wpp/downloads/ | | | CC BY 3.0 IGO | | Pendiente |",
    "| E2 | DANE - proyecciones nacionales 1950-2070 por sexo y edad | https://www.dane.gov.co/estadisticas-por-tema/demografia-y-poblacion/proyecciones-de-poblacion | | | Verificar | | Pendiente |",
    "| E3 | Parámetros pensionales de Colombia (edades, cotización, Ley 2381 de 2024) | Fuente oficial por confirmar | | | | | Pendiente |",
    "| E4 | Informalidad laboral (DANE, GEIH) | Por confirmar | | | | | Pendiente |",
    "| E5 | Fronteras mundiales (Natural Earth / rnaturalearth) | Por confirmar | | | | | Pendiente |"
  ), f_registro, useBytes = TRUE)
  cat("Plantilla creada:", f_registro, "\n")
} else {
  cat("Ya existe:", f_registro, "\n")
}
cat("Archivos en data/raw/externos/:\n  ",
    paste(list.files(dir_ext), collapse = "\n   "), "\n")


# ---- 5. Salidas --------------------------------------------------------------
write.csv(tabla_umbral, file.path(CFG$dir_tablas, "02_umbral_universo.csv"),    row.names = FALSE)
write.csv(rank_vel,     file.path(CFG$dir_tablas, "02_ranking_velocidad.csv"),  row.names = FALSE)
write.csv(orden_pi,     file.path(CFG$dir_tablas, "02_orden_bandas_pi.csv"),    row.names = FALSE)
write.csv(resumen_mig,  file.path(CFG$dir_tablas, "02_efecto_migracion.csv"),   row.names = FALSE)

# dbDisconnect(con, shutdown = TRUE)
