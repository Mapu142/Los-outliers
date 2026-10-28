# ==============================================================================
# ASA DataQuest 2026 - WPP2024
# Script 03b: Diagnóstico de la población por edad de la ONU y de la versión del DANE
# ------------------------------------------------------------------------------
# El script 03 dejó tres alertas abiertas:
#   A. La suma por edades difiere de TPopulation1July hasta 2.2 % (esperado: ~0).
#   B. La mediana calculada está ~1.0 año por encima de MedianAgePop.
#   C. El Excel del DANE reproduce el tramo histórico del PDF pero no el proyectado.
# Este script localiza el origen de A y B y lee los metadatos del Excel para C.
# NO modifica ningún dato; solo imprime evidencia y guarda tablas en output/tablas/.
# Ejecutar de arriba hacia abajo, desde la raíz del proyecto.
# ==============================================================================

# ---- 0. Entorno --------------------------------------------------------------
if (!file.exists("R/config.R")) stop("Abre el proyecto (.Rproj) o fija setwd() en la raíz.")
paquetes <- c("DBI", "duckdb", "dplyr", "tidyr", "glue", "tibble", "readxl")
invisible(lapply(paquetes, library, character.only = TRUE))
source("R/config.R",      encoding = "UTF-8")
source("R/utils_datos.R", encoding = "UTF-8")
crear_directorios()

con <- conectar_duckdb(if (exists("con")) con else NULL)
dbExecute(con, glue("CREATE OR REPLACE VIEW wpp AS
                     SELECT * FROM read_parquet('{file.path(CFG$dir_clean, CFG$f_parquet)}')"))

buscar_externo <- function(patron) {
  list.files(CFG$dir_externos, pattern = patron, recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
}
f1 <- buscar_externo("^WPP2024_PopulationBySingleAgeSex_Medium_1950-2023\\.csv(\\.gz)?$")[1]
f2 <- buscar_externo("^WPP2024_PopulationBySingleAgeSex_Medium_2024-2100\\.csv(\\.gz)?$")[1]
stopifnot(!is.na(f1), !is.na(f2))
lista_f <- paste0("'", normalizePath(c(f1, f2), winslash = "/"), "'", collapse = ", ")

dbExecute(con, glue("
  CREATE OR REPLACE VIEW un_edad AS
  SELECT LocID, Time, AgeGrpStart AS edad, PopMale, PopFemale, PopTotal
  FROM read_csv_auto([{lista_f}], header = TRUE, sample_size = -1, union_by_name = true)
  WHERE Variant = 'Medium' AND LocID IN (SELECT DISTINCT LocID FROM wpp)"))
dbExecute(con, "
  CREATE OR REPLACE TABLE un_tot AS
  SELECT LocID, Time, SUM(PopTotal) AS pob_total, SUM(PopMale) AS pob_h, SUM(PopFemale) AS pob_m
  FROM un_edad GROUP BY LocID, Time")
dbExecute(con, "
  CREATE OR REPLACE TABLE un_mediana AS
  WITH c AS (
    SELECT LocID, Time, edad, PopTotal AS pob,
           SUM(PopTotal) OVER (PARTITION BY LocID, Time ORDER BY edad) AS acum,
           SUM(PopTotal) OVER (PARTITION BY LocID, Time)               AS total
    FROM un_edad),
  m AS (
    SELECT LocID, Time, edad + (0.5 * total - (acum - pob)) / pob AS mediana_calc,
           ROW_NUMBER() OVER (PARTITION BY LocID, Time ORDER BY edad) AS rn
    FROM c WHERE acum >= 0.5 * total)
  SELECT LocID, Time, mediana_calc FROM m WHERE rn = 1")


# ---- A. Suma por edades frente a TPopulation1July ----------------------------
seccion("A. SUMA POR EDADES FRENTE A TPopulation1July")

dif_tot <- dbGetQuery(con, "
  SELECT e.LocID, w.ISO3_code, w.Location, e.Time, e.pob_total,
         w.TPopulation1July AS ref, (e.pob_total - w.TPopulation1July) / w.TPopulation1July AS dif_rel,
         (e.pob_h - w.TPopulationMale1July)   / w.TPopulationMale1July   AS dif_rel_h,
         (e.pob_m - w.TPopulationFemale1July) / w.TPopulationFemale1July AS dif_rel_m
  FROM un_tot e JOIN wpp w ON e.LocID = w.LocID AND e.Time = w.Time") |>
  mutate(tramo = if_else(Time <= CFG$ultimo_anio_estimado, "1950-2023", "2024-2100"))

cat("Distribución de |diferencia relativa| (suma por edades frente a TPopulation1July):\n")
print(quantile(abs(dif_tot$dif_rel), c(0.5, 0.9, 0.99, 0.999, 1)), digits = 3)

cat("\nPor tramo:\n")
ver(dif_tot |> group_by(tramo) |>
      summarise(filas = n(), mediana = median(abs(dif_rel)), p99 = quantile(abs(dif_rel), 0.99),
                maximo = max(abs(dif_rel)),
                n_mayor_1e4 = sum(abs(dif_rel) > 1e-4), .groups = "drop"))

cat("\nDiez peores país-año:\n")
ver(dif_tot |> arrange(desc(abs(dif_rel))) |>
      transmute(ISO3_code, Location, Time, pob_edades = round(pob_total, 3), ref = round(ref, 3),
                dif_pct = round(100 * dif_rel, 3)) |> head(10))

cat("\nCorrelación entre error de hombres y de mujeres (¿el error es de edades o de sexo?):",
    round(cor(dif_tot$dif_rel_h, dif_tot$dif_rel_m, use = "complete.obs"), 3), "\n")
write.csv(dif_tot |> arrange(desc(abs(dif_rel))) |> head(500),
          file.path(CFG$dir_tablas, "03b_peores_totales.csv"), row.names = FALSE)


# ---- B. Mediana calculada frente a MedianAgePop ------------------------------
seccion("B. MEDIANA CALCULADA FRENTE A MedianAgePop")

dif_med <- dbGetQuery(con, "
  SELECT m.LocID, w.ISO3_code, w.Location, m.Time, m.mediana_calc, w.MedianAgePop,
         m.mediana_calc - w.MedianAgePop AS dif
  FROM un_mediana m JOIN wpp w ON m.LocID = w.LocID AND m.Time = w.Time") |>
  mutate(tramo = if_else(Time <= CFG$ultimo_anio_estimado, "1950-2023", "2024-2100"))

cat("Distribución de (mediana calculada - MedianAgePop):\n")
print(quantile(dif_med$dif, c(0, 0.05, 0.25, 0.5, 0.75, 0.95, 1)), digits = 3)
cat(sprintf("\nProporción de filas con diferencia dentro de 1.0 ± 0.1: %.1f %%\n",
            100 * mean(abs(dif_med$dif - 1) <= 0.1)))
cat(sprintf("Proporción de filas con diferencia dentro de 0.5 ± 0.1: %.1f %%\n",
            100 * mean(abs(dif_med$dif - 0.5) <= 0.1)))
cat(sprintf("Desviación estándar de la diferencia: %.3f años\n", sd(dif_med$dif)))

cat("\nPor tramo:\n")
ver(dif_med |> group_by(tramo) |>
      summarise(filas = n(), media = mean(dif), desv = sd(dif), min = min(dif), max = max(dif),
                .groups = "drop"))

cat("\nColombia:\n")
ver(dif_med |> filter(ISO3_code == "COL", Time %in% c(1950, 1975, 2000, 2023, 2050, 2075, 2100)) |>
      transmute(Time, mediana_calc = round(mediana_calc, 2), MedianAgePop = round(MedianAgePop, 2),
                dif = round(dif, 2)))

cat("\nPaíses con la mayor y la menor diferencia media:\n")
por_pais <- dif_med |> group_by(ISO3_code, Location) |>
  summarise(dif_media = mean(dif), .groups = "drop") |> arrange(desc(dif_media))
ver(bind_rows(head(por_pais, 5), tail(por_pais, 5)))
write.csv(por_pais, file.path(CFG$dir_tablas, "03b_dif_mediana_por_pais.csv"), row.names = FALSE)

cat("\nLectura:\n",
    " - Diferencia casi constante (desv. pequeña) => diferencia de CONVENCIÓN en cómo la ONU calcula MedianAgePop.\n",
    " - Diferencia que varía mucho entre países o tramos => posible problema de edades o de fechas.\n", sep = "")


# ---- C. Metadatos del Excel del DANE -----------------------------------------
seccion("C. METADATOS DEL EXCEL DEL DANE (2018-2070)")

f_dane <- buscar_externo("PPED-AreaSexoEdadNac-2018-2070.*\\.xlsx?$")[1]
for (hoja in c("Índice", "PPED")) {
  if (hoja %in% excel_sheets(f_dane)) {
    cat("\nHoja:", hoja, "\n")
    x <- read_excel(f_dane, sheet = hoja, col_names = FALSE, n_max = 40, .name_repair = "minimal")
    x <- x[rowSums(!is.na(x)) > 0, colSums(!is.na(x)) > 0, drop = FALSE]
    print(as.data.frame(x), na.print = "", right = FALSE, max = 4000)
  }
}
cat("\nBusca en estas hojas: fecha de publicación, versión, 'actualización', nota sobre COVID-19\n",
    "o sobre migración. Esa información va a FUENTES.md (campo 'versión').\n", sep = "")

# dbDisconnect(con, shutdown = TRUE)
