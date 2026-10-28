# ==============================================================================
# ASA DataQuest 2026 - WPP2024
# Script 01: Verificación de viabilidad de la propuesta de proyecto
# ------------------------------------------------------------------------------
# Objetivo: comprobar con los datos reales qué partes de la propuesta se pueden
# hacer con los archivos entregados y con qué magnitudes, ANTES de modelar.
#
# Entradas : data/clean/wpp_paises_medium_suppl.parquet (script 00)
#            data/raw/WPP2024_..._OtherVariants_csv.gz   (solo para la sección 5)
# Salidas  : output/tablas/01_*.csv
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

PAIS <- "COL"   # país de estudio; cambiar aquí para otro caso


# ---- 1. ¿Hay estructura por edad? (condiciona la Relación de Soporte) --------
seccion("1. ¿EXISTEN POBLACIONES POR GRUPO DE EDAD EN LA TABLA MAESTRA?")

cols_wpp <- dbGetQuery(con, "DESCRIBE wpp")$column_name
cols_pop <- grep("Pop|Age", cols_wpp, value = TRUE)
# LBsurvivingAge1 = nacidos vivos que sobreviven al año 1; NO es población por edad
cols_pop <- setdiff(cols_pop, "LBsurvivingAge1")
cat("Columnas que mencionan 'Pop' o 'Age':\n  ", paste(cols_pop, collapse = ", "), "\n")

esperadas_sin_edad <- c("TPopulation1Jan", "TPopulation1July", "TPopulationMale1July",
                        "TPopulationFemale1July", "PopDensity", "PopSexRatio",
                        "MedianAgePop", "PopChange", "PopGrowthRate")
verificar(length(setdiff(cols_pop, esperadas_sin_edad)) == 0,
          "NO hay población por grupo de edad: la Relación de Soporte (15-64)/(65+) no es calculable con estos archivos.",
          paste("Columnas inesperadas:", paste(setdiff(cols_pop, esperadas_sin_edad), collapse = ", ")),
          fatal = FALSE)


# ---- 2. Trayectoria del país de estudio --------------------------------------
seccion(paste("2. TRAYECTORIA:", PAIS))

anios_ref <- c(1950, 1975, 2000, 2023, 2050, 2075, 2100)
tray <- dbGetQuery(con, glue("
  SELECT Time, tipo_dato,
         ROUND(MedianAgePop, 1) AS edad_mediana,
         ROUND(TFR, 2)          AS tfr,
         ROUND(LEx, 1)          AS lex,
         ROUND(LE60, 1)         AS le60,
         ROUND(LE65, 1)         AS le65,
         ROUND(Births / NULLIF(Deaths, 0), 2) AS indice_vital
  FROM wpp WHERE ISO3_code = '{PAIS}' AND Time IN ({paste(anios_ref, collapse = ',')})
  ORDER BY Time"))
ver(tray)
cat("(Compara con las cifras ilustrativas de la propuesta: edad mediana 18 -> 31 -> 45.)\n")


# ---- 3. Velocidad de envejecimiento (diferencia finita a 10 años) ------------
seccion("3. VELOCIDAD DE ENVEJECIMIENTO (años de edad mediana ganados por década)")

vel_pais <- dbGetQuery(con, glue("
  SELECT Time, ROUND(MedianAgePop, 1) AS edad_mediana,
         ROUND(MedianAgePop - LAG(MedianAgePop, 10) OVER (ORDER BY Time), 1) AS ganancia_10a
  FROM wpp WHERE ISO3_code = '{PAIS}' ORDER BY Time")) |>
  filter(Time %% 10 == 0, !is.na(ganancia_10a))
ver(vel_pais)

top_vel <- dbGetQuery(con, glue("
  WITH g AS (
    SELECT ISO3_code, Location, Time,
           MedianAgePop - LAG(MedianAgePop, 10) OVER (PARTITION BY ISO3_code ORDER BY Time) AS gan10
    FROM wpp)
  SELECT ISO3_code, Location,
         ROUND(MAX(gan10), 1) AS max_ganancia_10a,
         arg_max(Time, gan10) AS anio_del_maximo
  FROM g WHERE Time >= {CFG$ultimo_anio_estimado + 1}
  GROUP BY 1, 2 ORDER BY max_ganancia_10a DESC LIMIT 10"))
cat("\nDiez países con mayor ganancia de edad mediana en una década (proyección):\n")
ver(top_vel)


# ---- 4. Índice vital (Births / Deaths) ---------------------------------------
seccion("4. ÍNDICE VITAL = Births / Deaths")

# Nota: NO es el 'reemplazo generacional' demográfico (eso es NRR, ya en los datos).
iv_anio <- dbGetQuery(con, "
  SELECT Time,
         SUM(CASE WHEN Births < Deaths THEN 1 ELSE 0 END) AS paises_decrecimiento_natural,
         COUNT(*) AS paises
  FROM wpp WHERE Time IN (1950, 1990, 2023, 2050, 2075, 2100)
  GROUP BY Time ORDER BY Time")
ver(iv_anio)

primer_iv <- dbGetQuery(con, glue("
  SELECT MIN(Time) FILTER (WHERE Births < Deaths) AS primer_anio_indice_menor_1
  FROM wpp WHERE ISO3_code = '{PAIS}'"))
cat("\nPrimer año con Births < Deaths en", PAIS, ":\n"); ver(primer_iv)


# ---- 5. Incertidumbre oficial de la edad mediana (OtherVariants) -------------
seccion(paste("5. INCERTIDUMBRE OFICIAL: EDAD MEDIANA EN", PAIS))

variantes_ref <- c("High", "Low", "Zero migration", "Constant fertility",
                   "Lower 95 PI", "Lower 80 PI", "Median PI", "Upper 80 PI", "Upper 95 PI")
lista_var <- paste(sprintf("'%s'", variantes_ref), collapse = ", ")
unc <- dbGetQuery(con, glue("
  SELECT Variant, Time, ROUND(MedianAgePop, 1) AS edad_mediana
  FROM other_raw
  WHERE ISO3_code = '{PAIS}' AND Time IN (2050, 2100)
    AND Variant IN ({lista_var})
  UNION ALL
  SELECT 'Medium' AS Variant, Time, ROUND(MedianAgePop, 1)
  FROM wpp WHERE ISO3_code = '{PAIS}' AND Time IN (2050, 2100)")) |>
  arrange(Time, edad_mediana)
ver(unc)
cat("\nLectura: el ancho entre 'Lower 80 PI' y 'Upper 80 PI' es la incertidumbre oficial.\n",
    "Un pronóstico propio solo 'discrepa' de la ONU si cae FUERA de esa banda.\n", sep = "")


# ---- 6. Alcance máximo de una validación honesta -----------------------------
seccion("6. VENTANA DE VALIDACIÓN POSIBLE")

n_est <- CFG$ultimo_anio_estimado - CFG$primer_anio + 1
n_proy <- CFG$ultimo_anio_analisis - CFG$ultimo_anio_estimado
cat(sprintf("Años observados por país: %d | años a proyectar: %d (horizonte/historia = %.2f)\n",
            n_est, n_proy, n_proy / n_est))
cat(sprintf("Con %d años de historia, una validación por ventana móvil solo puede comprobar\n", n_est),
    sprintf("horizontes de ~20-30 años; el horizonte de %d años no se puede validar.\n", n_proy), sep = "")

write.csv(tray,    file.path(CFG$dir_tablas, "01_trayectoria_pais.csv"),    row.names = FALSE)
write.csv(top_vel, file.path(CFG$dir_tablas, "01_top_velocidad_envejecimiento.csv"), row.names = FALSE)
write.csv(unc,     file.path(CFG$dir_tablas, "01_incertidumbre_edad_mediana.csv"), row.names = FALSE)

# dbDisconnect(con, shutdown = TRUE)