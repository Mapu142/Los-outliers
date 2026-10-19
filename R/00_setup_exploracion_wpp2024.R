# ==============================================================================
# ASA DataQuest 2026 - WPP2024
# Script 00: Configuración, conexión duckdb, carga, validación y exploración inicial
# ------------------------------------------------------------------------------
# Estructura de carpetas esperada (relativa al proyecto de RStudio):
#   data/raw/   -> los 3 archivos de la ONU + el suplemento (SIN modificar)
#   data/clean/ -> salidas de este script (parquet / rds)
#   R/          -> funciones reutilizables (futuro)
#
# Archivos esperados en data/raw/:
#   WPP2024_Demographic_Indicators_Medium_csv.gz
#   WPP2024_Demographic_Indicators_OtherVariants_csv.gz
#   WPP2024_Demographic_Indicators_notes.csv
#   WPP2024_Supplement_Births_and_LE60.csv
# ==============================================================================

# ---- 0. Paquetes -------------------------------------------------------------
paquetes <- c("DBI", "duckdb", "dplyr", "tidyr", "ggplot2", "glue", "scales")
faltan <- setdiff(paquetes, rownames(installed.packages()))
if (length(faltan) > 0) install.packages(faltan)
invisible(lapply(paquetes, library, character.only = TRUE))


# ---- 1. Configuración global (único lugar donde se tocan rutas y constantes) --
CFG <- list(
  dir_raw    = "data/raw",
  dir_clean  = "data/clean",
  f_medium   = "WPP2024_Demographic_Indicators_Medium_csv.gz",
  f_other    = "WPP2024_Demographic_Indicators_OtherVariants_csv.gz",
  f_notes    = "WPP2024_Demographic_Indicators_notes.csv",
  f_suppl    = "WPP2024_Supplement_Births_and_LE60.csv",
  ultimo_anio_estimado = 2023L,   # <= 2023 estimaciones; >= 2024 proyecciones
  tol_births = 0.0011,   # 0.001 documentado + margen por punto flotante
  ultimo_anio_analisis = 2100L   # 2101 solo trae TPopulation1Jan
)
dir.create(CFG$dir_clean, showWarnings = FALSE, recursive = TRUE)

ruta <- function(archivo) normalizePath(file.path(CFG$dir_raw, archivo), mustWork = TRUE)

# Utilidad para imprimir encabezados de sección en consola
seccion <- function(txt) cat("\n", strrep("=", 70), "\n", txt, "\n", strrep("=", 70), "\n", sep = "")


# ---- 2. Conexión duckdb y vistas sobre los archivos crudos -------------------
# Las vistas NO cargan los datos en RAM: duckdb lee el .gz bajo demanda.
con <- dbConnect(duckdb::duckdb(), dbdir = ":memory:")
# Al terminar la sesión: dbDisconnect(con, shutdown = TRUE)

dbExecute(con, glue("
  CREATE OR REPLACE VIEW medium_raw AS
  SELECT * FROM read_csv_auto('{ruta(CFG$f_medium)}',
                              header = TRUE, sample_size = -1)"))

dbExecute(con, glue("
  CREATE OR REPLACE VIEW other_raw AS
  SELECT * FROM read_csv_auto('{ruta(CFG$f_other)}',
                              header = TRUE, sample_size = -1)"))

dbExecute(con, glue("
  CREATE OR REPLACE VIEW suppl_raw AS
  SELECT * FROM read_csv_auto('{ruta(CFG$f_suppl)}',
                              header = TRUE, sample_size = -1)"))

# Nota: a diferencia de pandas, duckdb NO interpreta "NA" como nulo, por lo que
# Namibia (ISO3 = "NAM") y otros códigos no se ven afectados. Las celdas vacías
# sí se leen como NULL.

notes <- read.csv(ruta(CFG$f_notes), fileEncoding = "UTF-8-BOM",
                  stringsAsFactors = FALSE)


# ---- 3. Inspección de esquemas -----------------------------------------------
seccion("3. ESQUEMAS")

# Imprime cualquier data.frame completo como tibble (evita el error de n = Inf)
ver <- function(x) print(tibble::as_tibble(x), n = Inf)

esq_medium <- dbGetQuery(con, "DESCRIBE medium_raw")
esq_other  <- dbGetQuery(con, "DESCRIBE other_raw")
esq_suppl  <- dbGetQuery(con, "DESCRIBE suppl_raw")

cat("Medium      :", nrow(esq_medium), "columnas\n")
cat("OtherVariants:", nrow(esq_other),  "columnas\n")
cat("Suplemento  :", nrow(esq_suppl),  "columnas\n")

# Columnas identificadoras vs. indicadores (esperado: ~54 indicadores)
cols_id <- c("SortOrder", "LocID", "Notes", "ISO3_code", "ISO2_code", "SDMX_code",
             "LocTypeID", "LocTypeName", "ParentID", "Location", "VarID",
             "Variant", "Time")
cols_ind <- setdiff(esq_medium$column_name, cols_id)
cat("Indicadores detectados en Medium:", length(cols_ind), "(esperado: 54)\n")

# Verificación crítica: las 5 variables del suplemento NO deben estar en Medium
vars_suppl <- c("BirthsMale", "BirthsFemale", "LE60", "LE60Male", "LE60Female")
cat("Variables del suplemento presentes en Medium (debe ser vacío): ",
    paste(intersect(vars_suppl, esq_medium$column_name), collapse = ", "), "\n")

ver(esq_medium[, c("column_name", "column_type")])


# ---- 4. Validaciones estructurales del archivo Medium ------------------------
seccion("4. VALIDACIONES DE ESTRUCTURA (MEDIUM)")

# 4.1 Dimensiones y rango temporal
dim_medium <- dbGetQuery(con, "
  SELECT COUNT(*) AS filas,
         COUNT(DISTINCT LocID) AS ubicaciones,
         MIN(Time) AS t_min, MAX(Time) AS t_max
  FROM medium_raw")
print(dim_medium)   # esperado: 84,360 filas; 1950-2101

# 4.2 La variante debe ser única ("Medium")
variantes <- dbGetQuery(con, "SELECT Variant, COUNT(*) AS n FROM medium_raw GROUP BY 1")
print(variantes)
stopifnot(nrow(variantes) == 1, variantes$Variant == "Medium")

# 4.3 Unicidad de la llave (LocID, Time)
dup <- dbGetQuery(con, "
  SELECT COUNT(*) AS n_dup FROM (
    SELECT LocID, Time FROM medium_raw GROUP BY 1, 2 HAVING COUNT(*) > 1)")
stopifnot(dup$n_dup == 0)
cat("OK: llave (LocID, Time) única.\n")

# 4.4 Tipos de ubicación (LocTypeName NO es confiable por sí solo)
tipos <- dbGetQuery(con, "
  SELECT LocTypeName,
         COUNT(DISTINCT LocID) AS ubicaciones,
         COUNT(DISTINCT CASE WHEN ISO3_code IS NOT NULL AND TRIM(ISO3_code) <> ''
                             THEN LocID END) AS con_iso3
  FROM medium_raw GROUP BY 1 ORDER BY ubicaciones DESC")
print(tipos)


# ---- 5. Regla de países: ISO3_code no nulo -----------------------------------
seccion("5. AISLAMIENTO DE PAÍSES (ISO3_code no nulo)")

dbExecute(con, "
  CREATE OR REPLACE VIEW medium_paises AS
  SELECT * FROM medium_raw
  WHERE ISO3_code IS NOT NULL AND TRIM(ISO3_code) <> ''")

dbExecute(con, "
  CREATE OR REPLACE VIEW medium_agregados AS
  SELECT * FROM medium_raw
  WHERE ISO3_code IS NULL OR TRIM(ISO3_code) = ''")

n_paises <- dbGetQuery(con, "SELECT COUNT(DISTINCT LocID) n FROM medium_paises")$n
n_agreg  <- dbGetQuery(con, "SELECT COUNT(DISTINCT LocID) n FROM medium_agregados")$n
cat("Países/áreas (ISO3):", n_paises, "| Agregados:", n_agreg, "\n")

# ---- 5b. Prueba anti doble-conteo: suma de países vs. fila 'World' -----------
chk_mundo <- dbGetQuery(con, "
  WITH p AS (SELECT Time, SUM(TPopulation1July) AS suma_paises
             FROM medium_paises GROUP BY Time),
       w AS (SELECT Time, TPopulation1July AS mundo
             FROM medium_agregados WHERE Location = 'World')
  SELECT p.Time, p.suma_paises, w.mundo,
         ROUND(100 * (p.suma_paises - w.mundo) / w.mundo, 4) AS dif_pct
  FROM p JOIN w USING (Time) ORDER BY Time")

anios_na <- chk_mundo$Time[is.na(chk_mundo$dif_pct)]
cat("Años con diferencia NA (esperado: 2101):", paste(anios_na, collapse = ", "), "\n")
cat("Diferencia máx. |suma países - World| (%):",
    max(abs(chk_mundo$dif_pct), na.rm = TRUE), "\n")
stopifnot(max(abs(chk_mundo$dif_pct), na.rm = TRUE) < 0.01)   # falla si hay doble conteo

# ---- 5c. Diagnóstico del año 2101 sobre TODOS los indicadores ----------------
sql_2101 <- paste0(
  sprintf("SUM(CASE WHEN \"%s\" IS NOT NULL THEN 1 ELSE 0 END) AS \"%s\"",
          cols_ind, cols_ind), collapse = ",\n  ")

pobl_2101 <- dbGetQuery(con, glue("
  SELECT {sql_2101} FROM medium_paises WHERE Time = 2101")) |>
  tidyr::pivot_longer(everything(), names_to = "indicador", values_to = "n_con_dato") |>
  filter(n_con_dato > 0)

cat("Indicadores con datos en 2101 (países):\n")
ver(pobl_2101)   # esperado: solo TPopulation1Jan

# ---- 6. Valores faltantes por indicador (solo países) ------------------------
seccion("6. VALORES FALTANTES (países)")

sql_na <- paste0(
  sprintf("SUM(CASE WHEN \"%s\" IS NULL THEN 1 ELSE 0 END) AS \"%s\"", cols_ind, cols_ind),
  collapse = ",\n  ")

na_wide <- dbGetQuery(con, glue("SELECT {sql_na} FROM medium_paises"))
total_p <- dbGetQuery(con, "SELECT COUNT(*) n FROM medium_paises")$n

na_tab <- na_wide |>
  tidyr::pivot_longer(everything(), names_to = "indicador", values_to = "n_na") |>
  mutate(pct_na = round(100 * n_na / total_p, 2)) |>
  arrange(desc(n_na))

ver(na_tab |> filter(n_na > 0))
if (all(na_tab$n_na == 0)) cat("Sin valores faltantes en indicadores de países.\n")


# ---- 7. Suplemento: validación y unión ---------------------------------------
seccion("7. SUPLEMENTO (Births by sex + LE60)")

dim_suppl <- dbGetQuery(con, "
  SELECT COUNT(*) AS filas, COUNT(DISTINCT LocID) AS ubicaciones,
         MIN(Time) AS t_min, MAX(Time) AS t_max FROM suppl_raw")
print(dim_suppl)   # esperado: 35,636 filas; 236 ubicaciones; 1950-2100

# 7.1 ¿Qué países del Medium NO están en el suplemento? (esperado: Holy See)
sin_suppl <- dbGetQuery(con, "
  SELECT DISTINCT m.LocID, m.ISO3_code, m.Location
  FROM medium_paises m
  WHERE m.LocID NOT IN (SELECT DISTINCT LocID FROM suppl_raw)")
cat("Países en Medium sin filas en el suplemento:\n"); print(sin_suppl)

# 7.2 Consistencia interna: Births_M + Births_F ≈ Births (tolerancia 0.001)
chk_births <- dbGetQuery(con, glue("
  SELECT COUNT(*) AS n_comparadas,
         SUM(CASE WHEN ABS((s.BirthsMale + s.BirthsFemale) - m.Births) > {CFG$tol_births}
                  THEN 1 ELSE 0 END) AS n_fuera_tol
  FROM suppl_raw s JOIN medium_paises m USING (LocID, Time)"))
print(chk_births)

# 7.3 LE60 (ambos sexos) debe estar entre LE60Male y LE60Female
chk_le60 <- dbGetQuery(con, "
  SELECT COUNT(*) AS n,
         SUM(CASE WHEN LE60 < LEAST(LE60Male, LE60Female) - 1e-9
                    OR LE60 > GREATEST(LE60Male, LE60Female) + 1e-9
                  THEN 1 ELSE 0 END) AS n_incoherentes
  FROM suppl_raw")
print(chk_le60)

# 7.4 Vista unificada país-año (LEFT JOIN: el Medium manda)
# Ojo: el suplemento llega hasta 2100; Medium hasta 2101 => 2101 quedará NA.
dbExecute(con, glue("
  CREATE OR REPLACE VIEW wpp_paises AS
  SELECT m.*,
         s.BirthsMale, s.BirthsFemale, s.LE60, s.LE60Male, s.LE60Female,
         CASE WHEN m.Time <= {CFG$ultimo_anio_estimado}
              THEN 'Estimación' ELSE 'Proyección' END AS tipo_dato
  FROM medium_paises m
  LEFT JOIN suppl_raw s ON m.LocID = s.LocID AND m.Time = s.Time
  WHERE m.Time <= {CFG$ultimo_anio_analisis}"))

na_2101 <- dbGetQuery(con, "
  SELECT Time, SUM(CASE WHEN LE60 IS NULL THEN 1 ELSE 0 END) AS n_na_le60, COUNT(*) n
  FROM wpp_paises WHERE LE60 IS NULL GROUP BY Time ORDER BY Time")
cat("Años con LE60 faltante tras la unión:\n")

chk_le60_na <- dbGetQuery(con, "
  SELECT Location, COUNT(*) AS n_na
  FROM wpp_paises WHERE LE60 IS NULL GROUP BY Location")
ver(chk_le60_na)   # esperado: solo Holy See

# ¿DoublingTime es NA solo cuando la población no crece?
ver(dbGetQuery(con, "
  SELECT CASE WHEN Time = 2101           THEN '2101 (sin datos)'
              WHEN PopGrowthRate <= 0    THEN 'Crecimiento <= 0'
              WHEN PopGrowthRate >  0    THEN 'Crecimiento > 0'
         END AS grupo,
         COUNT(*) AS n_filas,
         SUM(CASE WHEN DoublingTime IS NULL THEN 1 ELSE 0 END) AS n_na_doubling
  FROM medium_paises GROUP BY 1 ORDER BY 1"))

ver(dbGetQuery(con, "
  SELECT MAX(ABS((s.BirthsMale + s.BirthsFemale) - m.Births)) AS dif_max,
         SUM(CASE WHEN ABS((s.BirthsMale + s.BirthsFemale) - m.Births) > 0.0011
                  THEN 1 ELSE 0 END) AS n_fuera_real
  FROM suppl_raw s JOIN medium_paises m USING (LocID, Time)"))

ver(dbGetQuery(con, "
  SELECT tipo_dato,
         DoublingTime IS NULL AS doubling_na,
         COUNT(*) AS n,
         ROUND(MIN(PopGrowthRate), 4) AS crec_min,
         ROUND(MAX(PopGrowthRate), 4) AS crec_max
  FROM wpp_paises
  WHERE PopGrowthRate > 0
  GROUP BY 1, 2 ORDER BY 1, 2"))
# DoublingTime no tiene faltantes aleatorios, tiene censura estructural. Está censurado para las 15,938 filas con crecimiento ≤ 0.5 % (el 44.5 % del total).

# ---- 8. Exploración inicial de OtherVariants (sin cargarlo completo) ---------
seccion("8. OTHERVARIANTS (resumen vía SQL)")

var_tab <- dbGetQuery(con, "
  SELECT Variant, COUNT(*) AS filas, COUNT(DISTINCT LocID) AS ubicaciones,
         MIN(Time) AS t_min, MAX(Time) AS t_max
  FROM other_raw GROUP BY 1 ORDER BY 1")
ver(var_tab)
cat("Variantes distintas:", nrow(var_tab), "(esperado: 18)\n")


# ---- 9. Exploración descriptiva rápida ---------------------------------------
seccion("9. EXPLORACIÓN DESCRIPTIVA")

# 9.1 Resumen de indicadores clave en el último año de estimación
resumen_2023 <- dbGetQuery(con, glue("
  SELECT COUNT(*) AS n_paises,
         ROUND(MEDIAN(TFR), 2)      AS tfr_mediana,
         ROUND(MEDIAN(LEx), 1)      AS lex_mediana,
         ROUND(MEDIAN(MedianAgePop),1) AS edad_mediana_mediana,
         ROUND(SUM(TPopulation1July)/1e6, 2) AS poblacion_mundial_miles_de_millones
  FROM wpp_paises WHERE Time = {CFG$ultimo_anio_estimado}"))
print(resumen_2023)

# 9.2 Series globales (agregadas por SQL; solo ~152 filas llegan a R)
serie_global <- dbGetQuery(con, "
  SELECT Time,
         SUM(TPopulation1July) / 1e6 AS pob_miles_millones,
         SUM(Births)  AS nacimientos_miles,
         SUM(Deaths)  AS muertes_miles,
         SUM(NetMigrations) AS migracion_neta_miles
  FROM wpp_paises GROUP BY Time ORDER BY Time")

# Gráfico de control: población mundial con quiebre estimación/proyección
ggplot(serie_global, aes(Time, pob_miles_millones)) +
  geom_line(linewidth = 1, colour = "#0072B2") +
  geom_vline(xintercept = CFG$ultimo_anio_estimado + 0.5,
             linetype = "dashed", colour = "grey40") +
  annotate("text", x = CFG$ultimo_anio_estimado + 2, y = 2.5,
           label = "Proyección (Medium)", hjust = 0, colour = "grey30") +
  scale_y_continuous(labels = label_number(suffix = " mil M")) +
  labs(title = "Población mundial (suma de países, 1 de julio)",
       subtitle = "Gráfico de control: debe coincidir con la fila 'World' del UN",
       x = NULL, y = NULL, caption = "Fuente: UN WPP 2024, variante Medium") +
  theme_minimal(base_size = 12)

# 9.3 Distribución de TFR por año seleccionado (países)
tfr_sel <- dbGetQuery(con, "
  SELECT Time, ISO3_code, Location, TFR
  FROM wpp_paises WHERE Time IN (1950, 1990, 2023, 2060, 2100)")

ggplot(tfr_sel, aes(factor(Time), TFR)) +
  geom_hline(yintercept = 2.1, linetype = "dashed", colour = "firebrick") +
  geom_boxplot(fill = "#56B4E9", alpha = 0.6, outlier.alpha = 0.4) +
  labs(title = "Convergencia de la fecundidad hacia el nivel de reemplazo",
       subtitle = "Línea roja: TFR = 2.1 hijos por mujer",
       x = "Año", y = "TFR", caption = "Fuente: UN WPP 2024, variante Medium") +
  theme_minimal(base_size = 12)


# ---- 10. Persistencia de datos limpios ---------------------------------------
seccion("10. GUARDADO")

ruta_parquet <- file.path(CFG$dir_clean, "wpp_paises_medium_suppl.parquet")
dbExecute(con, glue("COPY (SELECT * FROM wpp_paises)
                     TO '{ruta_parquet}' (FORMAT PARQUET)"))

# Diccionario de indicadores listo para tooltips/etiquetas del Rmd y Shiny
saveRDS(notes, file.path(CFG$dir_clean, "diccionario_indicadores.rds"))

cat("Guardado:", ruta_parquet, "\n")
cat("Para continuar en otros scripts:\n",
    "  con <- dbConnect(duckdb::duckdb())\n",
    "  dbExecute(con, \"CREATE VIEW wpp AS SELECT * FROM read_parquet('", ruta_parquet, "')\")\n", sep = "")

# dbDisconnect(con, shutdown = TRUE)   # ejecutar al terminar la sesión
