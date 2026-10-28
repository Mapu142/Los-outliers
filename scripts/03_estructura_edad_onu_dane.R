# ==============================================================================
# ASA DataQuest 2026 - WPP2024
# Script 03: Estructura por edad (ONU y DANE) y soporte demográfico de Colombia
# ------------------------------------------------------------------------------
# Implementa P3 del PLAN_ANALITICO.md (D18-D21):
#   1. Cargar la población por edad simple de la ONU (fuente externa E1).
#   2. Validarla contra la tabla maestra (totales y edad mediana).
#   3. Calcular estructura por edad y relaciones de soporte (PSR) para los 237 países.
#   4. Cargar y empalmar las proyecciones nacionales del DANE (fuente externa E2).
#   5. Verificar la versión del DANE con los puntos de control del PDF (marzo 2023).
#   6. Comparar ONU frente a DANE para Colombia y calcular años de cruce de umbrales.
# Revisión (tras 03b): lectura robusta del Excel del DANE (hoja y área opcionales) y
# tratamiento explícito del desfase de +1 año entre mediana calculada y MedianAgePop (D21).
#
# Entradas : data/clean/wpp_paises_medium_suppl.parquet
#            data/raw/externos/ (archivos de la ONU por edad y Excel del DANE)
#            data/raw/externos/documentacion/checkpoints_dane.csv
# Salidas  : data/clean/un_estructura_edad.parquet ; data/clean/dane_estructura_edad.rds
#            output/tablas/03_*.csv ; output/figuras/03_*.png
# Ejecutar de arriba hacia abajo, desde la raíz del proyecto.
# ==============================================================================

# ---- 0. Entorno --------------------------------------------------------------
if (!file.exists("R/config.R")) stop("Abre el proyecto (.Rproj) o fija setwd() en la raíz.")
paquetes <- c("DBI", "duckdb", "dplyr", "tidyr", "glue", "tibble", "ggplot2",
              "scales", "readxl")
faltan <- setdiff(paquetes, rownames(installed.packages()))
if (length(faltan) > 0) install.packages(faltan)
invisible(lapply(paquetes, library, character.only = TRUE))
source("R/config.R",      encoding = "UTF-8")
source("R/utils_datos.R", encoding = "UTF-8")
source("R/tema.R",        encoding = "UTF-8")
crear_directorios()

con <- conectar_duckdb(if (exists("con")) con else NULL)
ruta_parquet <- file.path(CFG$dir_clean, CFG$f_parquet)
dbExecute(con, glue("CREATE OR REPLACE VIEW wpp AS
                     SELECT * FROM read_parquet('{ruta_parquet}')"))

PAIS <- "COL"
loc_col <- dbGetQuery(con, glue("SELECT DISTINCT LocID FROM wpp WHERE ISO3_code = '{PAIS}'"))$LocID
verificar(length(loc_col) == 1, paste0(PAIS, " -> LocID ", loc_col),
          "No se pudo identificar el LocID del país de estudio.")

buscar_externo <- function(patron) {
  list.files(CFG$dir_externos, pattern = patron, recursive = TRUE,
             full.names = TRUE, ignore.case = TRUE)
}
primero <- function(x) if (length(x) >= 1) normalizePath(x[1], winslash = "/") else NA_character_


# ---- 1. Localizar los archivos de población por edad de la ONU ---------------
seccion("1. ARCHIVOS DE POBLACIÓN POR EDAD DE LA ONU (E1)")

pat <- function(nucleo, tramo) sprintf("^WPP2024_%s_Medium_%s\\.csv(\\.gz)?$", nucleo, tramo)
f_jul_hist <- primero(buscar_externo(pat("PopulationBySingleAgeSex",          "1950-2023")))
f_jul_proy <- primero(buscar_externo(pat("PopulationBySingleAgeSex",          "2024-2100")))
f_ene_hist <- primero(buscar_externo(pat("Population1JanuaryBySingleAgeSex",  "1950-2023")))
f_ene_proy <- primero(buscar_externo(pat("Population1JanuaryBySingleAgeSex",  "2024-2100")))

estado <- tibble(
  archivo = c("1 de julio 1950-2023", "1 de julio 2024-2100",
              "1 de enero 1950-2023", "1 de enero 2024-2100"),
  encontrado = !is.na(c(f_jul_hist, f_jul_proy, f_ene_hist, f_ene_proy)))
ver(estado)

# La fecha de referencia debe ser UNA sola para toda la serie (D19).
# Preferida: 1 de julio (igual que TPopulation1July, MedianAgePop y el DANE, 30 de junio).
if (!is.na(f_jul_hist) && !is.na(f_jul_proy)) {
  BASE <- "julio"; archivos_un <- c(f_jul_hist, f_jul_proy)
} else if (!is.na(f_ene_hist) && !is.na(f_ene_proy)) {
  BASE <- "enero"; archivos_un <- c(f_ene_hist, f_ene_proy)
  warning("Falta el archivo de 1 de julio 2024-2100. Se usa la serie del 1 de enero ",
          "(completa 1950-2100). Para comparar con el DANE (30 de junio) se recomienda ",
          "descargar WPP2024_PopulationBySingleAgeSex_Medium_2024-2100.csv.gz.",
          call. = FALSE)
} else {
  stop("No hay un par completo (histórico + proyección) en la misma fecha de referencia. ",
       "Revisa data/raw/externos/.", call. = FALSE)
}
cat("Fecha de referencia usada:", BASE, "\n")
col_ref <- if (BASE == "julio") "TPopulation1July" else "TPopulation1Jan"


# ---- 2. Vistas y validación contra la tabla maestra --------------------------
seccion("2. VALIDACIÓN DE LA POBLACIÓN POR EDAD (ONU)")

lista_f <- paste0("'", archivos_un, "'", collapse = ", ")
dbExecute(con, glue("
  CREATE OR REPLACE VIEW un_edad AS
  SELECT LocID, Time, AgeGrpStart AS edad, PopMale, PopFemale, PopTotal
  FROM read_csv_auto([{lista_f}], header = TRUE, sample_size = -1, union_by_name = true)
  WHERE Variant = 'Medium' AND LocID IN (SELECT DISTINCT LocID FROM wpp)"))

rango_un <- dbGetQuery(con, "
  SELECT COUNT(DISTINCT LocID) AS ubicaciones, MIN(Time) AS t_min, MAX(Time) AS t_max,
         MIN(edad) AS edad_min, MAX(edad) AS edad_max, COUNT(*) AS filas
  FROM un_edad")
ver(rango_un)
verificar(rango_un$edad_min == 0 && rango_un$edad_max == 100,
          "Edades simples 0-100; el grupo 100 es '100 y más' (intervalo abierto).",
          "Rango de edades inesperado.", fatal = FALSE)
verificar(rango_un$t_min <= 1950 && rango_un$t_max >= 2100,
          paste0("Cobertura temporal ", rango_un$t_min, "-", rango_un$t_max, "."),
          "La serie de edades no cubre 1950-2100.", fatal = FALSE)

dbExecute(con, "
  CREATE OR REPLACE TABLE un_estructura AS
  SELECT LocID, Time,
         SUM(PopTotal)                                            AS pob_total,
         SUM(CASE WHEN edad <= 14             THEN PopTotal END)  AS pob_0_14,
         SUM(CASE WHEN edad BETWEEN 15 AND 59 THEN PopTotal END)  AS pob_15_59,
         SUM(CASE WHEN edad BETWEEN 15 AND 64 THEN PopTotal END)  AS pob_15_64,
         SUM(CASE WHEN edad >= 60             THEN PopTotal END)  AS pob_60p,
         SUM(CASE WHEN edad >= 65             THEN PopTotal END)  AS pob_65p
  FROM un_edad GROUP BY LocID, Time")

# Mediana por interpolación lineal dentro de la edad simple
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

# 2.1 La suma por edades debe reproducir la población total de la tabla maestra
chk_tot <- dbGetQuery(con, glue("
  SELECT COUNT(*) AS filas_comparadas,
         COUNT(DISTINCT e.LocID) AS paises,
         MAX(ABS(e.pob_total - w.{col_ref}) / w.{col_ref}) AS dif_rel_max
  FROM un_estructura e JOIN wpp w ON e.LocID = w.LocID AND e.Time = w.Time"))
ver(chk_tot)
cat(sprintf("  Diferencia relativa máx. global: %.2e (la domina Holy See; ver 2.1b para el universo).\n",
            chk_tot$dif_rel_max))

# 2.1b El máximo global lo domina Holy See (~0,5 mil habitantes: unas decenas de personas
# son un porcentaje grande). Se repite la prueba solo en el universo (>= 1 millón).
chk_tot_u <- dbGetQuery(con, glue("
  SELECT COUNT(DISTINCT e.LocID) AS paises,
         MAX(ABS(e.pob_total - w.{col_ref}) / w.{col_ref}) AS dif_rel_max,
         MAX(ABS(e.pob_total - w.{col_ref})) * 1000        AS dif_abs_max_personas
  FROM un_estructura e JOIN wpp w ON e.LocID = w.LocID AND e.Time = w.Time
  WHERE w.{col_ref} >= {CFG$umbral_universo_miles}"))
ver(chk_tot_u)
verificar(chk_tot_u$dif_rel_max < 1e-3,
          sprintf("En el universo (>= 1 millón) la suma por edades difiere de %s en menos de %.2f %%.",
                  col_ref, 100 * chk_tot_u$dif_rel_max),
          sprintf("Incluso en el universo la diferencia llega a %.2f %%: revisar fechas de referencia.",
                  100 * chk_tot_u$dif_rel_max), fatal = FALSE)

# 2.2 Mediana calculada frente a MedianAgePop (solo si la base es 1 de julio)
# Hallazgo del script 03b: la diferencia es CONSTANTE (~ +1,0 año, desv. ~0,02) en los
# 237 países y en todo el periodo. Es un desfase de convención, no un error de datos.
# Regla (D21): comparaciones ONU-DANE usan SIEMPRE mediana_calc en ambas fuentes
# (el desfase se cancela); al citar MedianAgePop de la ONU se usa la columna original.
OFFSET_MEDIANA <- NA_real_
if (BASE == "julio") {
  chk_med <- dbGetQuery(con, "
    SELECT COUNT(*) AS n,
           ROUND(AVG(m.mediana_calc - w.MedianAgePop), 3)    AS dif_media,
           ROUND(STDDEV(m.mediana_calc - w.MedianAgePop), 3) AS dif_desv,
           ROUND(MIN(m.mediana_calc - w.MedianAgePop), 3)    AS dif_min,
           ROUND(MAX(m.mediana_calc - w.MedianAgePop), 3)    AS dif_max
    FROM un_mediana m JOIN wpp w ON m.LocID = w.LocID AND m.Time = w.Time")
  ver(chk_med)
  OFFSET_MEDIANA <- chk_med$dif_media
  verificar(chk_med$dif_desv < 0.05,
            sprintf("Diferencia casi constante (media %+.2f años, desv. %.3f): desfase de convención (D21).",
                    chk_med$dif_media, chk_med$dif_desv),
            sprintf("La diferencia varía (desv. %.3f años): no es un desfase constante, revisar.",
                    chk_med$dif_desv), fatal = FALSE)
} else {
  cat("Base 1 de enero: no se compara la mediana con MedianAgePop (que es de 1 de julio).\n")
}


# ---- 3. Relaciones de soporte (PSR) para todos los países --------------------
seccion("3. SOPORTE DEMOGRÁFICO (PSR) - ONU")

# D18: dos definiciones. PSR65 = 15-64 / 65+ (internacional); PSR60 = 15-59 / 60+ (DANE).
un_psr <- dbGetQuery(con, "
  SELECT e.LocID, e.Time, e.pob_total, e.pob_0_14, e.pob_15_59, e.pob_15_64,
         e.pob_60p, e.pob_65p, m.mediana_calc,
         e.pob_15_64 / NULLIF(e.pob_65p, 0) AS psr65,
         e.pob_15_59 / NULLIF(e.pob_60p, 0) AS psr60
  FROM un_estructura e JOIN un_mediana m USING (LocID, Time)
  ORDER BY e.LocID, e.Time")

# Función: primer año con PSR bajo el umbral durante `racha` años seguidos (D15, D18)
anio_cruce <- function(anio, valor, umbral, racha = CFG$racha_cruce) {
  bajo <- valor < umbral
  if (length(bajo) < racha) return(NA_integer_)
  for (i in seq_len(length(bajo) - racha + 1)) {
    if (all(bajo[i:(i + racha - 1)])) return(as.integer(anio[i]))
  }
  NA_integer_
}

# Resumen mundial por país: años de cruce de cada umbral
paises_ref <- dbGetQuery(con, glue("
  SELECT DISTINCT LocID, ISO3_code, Location FROM wpp"))
cruces_paises <- un_psr |>
  filter(Time >= CFG$ultimo_anio_estimado) |>
  group_by(LocID) |>
  summarise(across(c(psr65, psr60), list(
    c3  = ~ anio_cruce(Time, .x, 3.0),
    c25 = ~ anio_cruce(Time, .x, 2.5)), .names = "{.col}_{.fn}"), .groups = "drop") |>
  left_join(paises_ref, by = "LocID")
cat("Países que cruzan PSR65 < 3.0 entre 2023 y 2100:",
    sum(!is.na(cruces_paises$psr65_c3)), "de", nrow(cruces_paises), "\n")

# Guardar la tabla maestra de estructura por edad (insumo de la Fase 2)
ruta_edad <- file.path(CFG$dir_clean, "un_estructura_edad.parquet")
dbWriteTable(con, "un_psr_tbl", un_psr, overwrite = TRUE)
dbExecute(con, glue("COPY un_psr_tbl TO '{ruta_edad}' (FORMAT PARQUET)"))
cat("Guardado:", ruta_edad, "\n")

un_col <- un_psr |> filter(LocID == loc_col)
cat("\nColombia (ONU), años de referencia:\n")
ver(un_col |> filter(Time %in% c(1950, 1975, 2000, 2023, 2035, 2050, 2070, 2100)) |>
      transmute(Time, pob_miles = round(pob_total), mediana = round(mediana_calc, 1),
                pct_60p = round(100 * pob_60p / pob_total, 1),
                psr65 = round(psr65, 2), psr60 = round(psr60, 2)))


# ---- 4. DANE: lectura, tidy y empalme (E2) -----------------------------------
seccion("4. DANE: PROYECCIONES NACIONALES POR EDAD SIMPLE (E2)")

f_dane_hist <- primero(buscar_externo("PPED-AreaSexoEdadNac-1950-2017.*\\.xlsx?$"))
f_dane_proy <- primero(buscar_externo("PPED-AreaSexoEdadNac-2018-2070.*\\.xlsx?$"))
verificar(!is.na(f_dane_hist) && !is.na(f_dane_proy),
          "Se encontraron los dos archivos del DANE (1950-2017 y 2018-2070).",
          "Faltan archivos del DANE en data/raw/externos/ (PPED-AreaSexoEdadNac-...xlsx).")
cat("Hojas 1950-2017:", paste(excel_sheets(f_dane_hist), collapse = " | "), "\n")
cat("Hojas 2018-2070:", paste(excel_sheets(f_dane_proy), collapse = " | "), "\n")

# --- Lectura robusta de los Excel del DANE ------------------------------------
# Estructura REAL de los dos archivos (verificada con capturas de pantalla):
#  * 1950-2017 (hoja 'Nacional_1950_2017'): UNA fila de encabezado (DP | DPNOM | AÑO |
#    ÁREA GEOGRÁFICA | Hombres_0 ... Mujeres_100), 3 filas por año (Cabecera, Centros
#    Poblados y Rural Disperso, Total) y pies de nota al final. "Actualización: marzo 2023".
#  * 2018-2070 (hoja 'PobNacionalxÁreaSexoEdad'): encabezado de DOS filas: AÑO en la fila 8
#    y los nombres por edad ('Hombres 0 años' ... 'Mujeres 100 años y más', y luego
#    'Total 0 años'...) en la fila 9. Hojas 'Índice' y 'PPED' son documentación.
#    "Actualizado el 18 de julio de 2025".
# Estrategia: leer cada hoja COMPLETA como texto y SIN encabezado (así los índices de fila
# son los de la matriz leída; read_excel(skip=) cuenta filas físicas y no coincide con la
# lectura que recorta filas vacías iniciales), localizar la fila con AÑO, decidir si los
# nombres por edad están en esa fila o en la siguiente, y construir los nombres combinando
# ambas filas.
patron_edad <- "^(Hombres?|Mujeres?)[ _]+[0-9]+"
patron_anio <- "^A.{1,2}O$"            # AÑO, tolerante a problemas de codificación de la Ñ
es_anio <- function(x) grepl(patron_anio, trimws(as.character(x)), ignore.case = TRUE)

leer_hoja_cruda <- function(archivo, hoja) {
  suppressMessages(read_excel(archivo, sheet = hoja, col_names = FALSE,
                              col_types = "text", .name_repair = "minimal"))
}

# Localiza la fila con AÑO (fa) y la fila que contiene los nombres por edad
analizar_cruda <- function(cr) {
  vacio <- list(fa = NA_integer_, fila_edad = NA_integer_, n_edad = 0L)
  if (nrow(cr) == 0 || ncol(cr) == 0) return(vacio)
  m <- as.matrix(cr)
  tope <- min(60L, nrow(m))
  fa <- which(apply(m[seq_len(tope), , drop = FALSE], 1, function(r) any(es_anio(r))))[1]
  if (is.na(fa)) return(vacio)
  cuenta <- function(i) {
    if (i > nrow(m)) return(0L)
    sum(grepl(patron_edad, trimws(m[i, ]), ignore.case = TRUE))
  }
  cands <- c(fa, fa + 1L)
  n <- vapply(cands, cuenta, integer(1))
  list(fa = as.integer(fa), fila_edad = as.integer(cands[which.max(n)]),
       n_edad = as.integer(max(n)))
}

# Devuelve un tibble de texto con nombres de columna ya combinados
leer_dane <- function(archivo) {
  hojas  <- excel_sheets(archivo)
  crudas <- lapply(hojas, function(h) leer_hoja_cruda(archivo, h))
  info   <- lapply(crudas, analizar_cruda)
  n_edad <- vapply(info, function(z) z$n_edad, integer(1))
  resumen <- paste0(hojas, " (cols. por edad: ", n_edad, ")", collapse = " | ")
  verificar(any(n_edad >= 100),
            paste0("Hoja de datos en ", basename(archivo), ": '", hojas[which.max(n_edad)], "'."),
            paste0("Ninguna hoja de ", basename(archivo), " tiene encabezado AÑO con columnas ",
                   "por edad. Hojas inspeccionadas: ", resumen))
  i   <- which.max(n_edad)
  inf <- info[[i]]
  m   <- as.matrix(crudas[[i]])
  
  n_a <- trimws(m[inf$fa, ])            # fila con AÑO / TERRITORIO / ÁREA
  n_e <- trimws(m[inf$fila_edad, ])     # fila con 'Hombres 0 años'... (puede ser la misma)
  nombres <- ifelse(!is.na(n_e) & n_e != "", n_e, n_a)
  nombres <- ifelse(is.na(nombres) | nombres == "",
                    paste0("sin_nombre_", seq_along(nombres)), nombres)
  nombres <- make.unique(nombres)
  
  ini <- max(inf$fa, inf$fila_edad) + 1L
  verificar(ini <= nrow(m), "Hay filas de datos debajo del encabezado.",
            paste("El encabezado termina en la última fila de", basename(archivo)))
  cuerpo <- m[ini:nrow(m), , drop = FALSE]
  colnames(cuerpo) <- nombres
  df <- tibble::as_tibble(cuerpo)
  df <- df[rowSums(!is.na(cuerpo)) > 0, , drop = FALSE]
  cat("  ", basename(archivo), " -> hoja '", hojas[i], "' | AÑO en la fila ", inf$fa,
      ", nombres por edad en la fila ", inf$fila_edad, " | ", nrow(df), " filas x ",
      ncol(df), " columnas.\n", sep = "")
  df
}

# Pasa de formato ancho a largo. Conserva solo Área = Total y descarta pies de nota.
dane_largo <- function(df) {
  col_anio <- grep(patron_anio, names(df), ignore.case = TRUE, value = TRUE)[1]
  col_area <- grep("^.?REA", names(df), ignore.case = TRUE, value = TRUE)[1]
  verificar(!is.na(col_anio), "Columna AÑO localizada.",
            paste("No hay columna AÑO. Primeras columnas:", paste(head(names(df), 8), collapse = " | ")))
  df$anio <- suppressWarnings(as.integer(as.numeric(df[[col_anio]])))
  df <- df |> filter(!is.na(anio))               # descarta pies de nota y filas vacías
  
  if (is.na(col_area)) {
    cat("  Sin columna de área: se asume una serie nacional (total).\n")
  } else {
    valores_area <- unique(trimws(as.character(df[[col_area]])))
    df <- df |> filter(tolower(trimws(as.character(.data[[col_area]]))) == "total")
    verificar(nrow(df) > 0, paste0("Filas con Área = Total (columna '", col_area, "')."),
              paste0("Ninguna fila con Área = Total. Valores en '", col_area, "': ",
                     paste(head(valores_area, 10), collapse = " | ")))
  }
  
  dup <- df |> count(anio) |> filter(n > 1)
  verificar(nrow(dup) == 0, "Una fila por año.",
            paste0("Años con más de una fila: ", paste(head(dup$anio, 10), collapse = ", "),
                   ". Hay otra dimensión sin filtrar. Columnas no-edad: ",
                   paste(head(setdiff(names(df), grep(patron_edad, names(df), value = TRUE)), 10),
                         collapse = " | ")))
  
  cols_edad <- grep(patron_edad, names(df), value = TRUE, ignore.case = TRUE)
  verificar(length(cols_edad) == 202,
            paste("Columnas por edad y sexo:", length(cols_edad), "(2 sexos x 101 edades)."),
            paste("Hay", length(cols_edad), "columnas por edad; se esperaban 202."), fatal = FALSE)
  
  df |>
    mutate(across(all_of(cols_edad), ~ suppressWarnings(as.numeric(.x)))) |>
    select(anio, all_of(cols_edad)) |>
    pivot_longer(-anio, names_to = "col", values_to = "pob") |>
    mutate(sexo = if_else(grepl("^Hombre", col, ignore.case = TRUE), "H", "M"),
           edad = as.integer(sub("^[A-Za-z]+[ _]+([0-9]+).*$", "\\1", col))) |>
    select(anio, sexo, edad, pob)
}

dane_h <- dane_largo(leer_dane(f_dane_hist))
dane_p <- dane_largo(leer_dane(f_dane_proy))
cat("  Histórico:", min(dane_h$anio), "-", max(dane_h$anio),
    "| Proyección:", min(dane_p$anio), "-", max(dane_p$anio), "\n")
verificar(!anyNA(dane_h$pob) && !anyNA(dane_p$pob),
          "Poblaciones numéricas sin faltantes en ambos archivos.",
          "Hay valores no numéricos en las columnas por edad.")

# Empalme: el año de corte no se duplica; ante solapamiento manda la serie 2018-2070 (base censo 2018)
solape <- intersect(unique(dane_h$anio), unique(dane_p$anio))
cat("Años en ambos archivos:", ifelse(length(solape) == 0, "ninguno", paste(solape, collapse = ", ")), "\n")
dane <- bind_rows(dane_h |> filter(!anio %in% dane_p$anio), dane_p) |> arrange(anio, sexo, edad)
cat("Serie empalmada:", min(dane$anio), "-", max(dane$anio), "| edades:", min(dane$edad), "-", max(dane$edad), "\n")
verificar(all(diff(sort(unique(dane$anio))) == 1), "Serie anual continua, sin años faltantes.",
          "Hay años faltantes en la serie empalmada del DANE.", fatal = FALSE)

mediana_edad <- function(edad, pob) {
  o <- order(edad); edad <- edad[o]; pob <- pob[o]
  acum <- cumsum(pob); total <- sum(pob)
  i <- which(acum >= 0.5 * total)[1]
  edad[i] + (0.5 * total - (acum[i] - pob[i])) / pob[i]
}

dane_ind <- dane |>
  group_by(anio, edad) |> summarise(pob = sum(pob), .groups = "drop") |>
  group_by(anio) |>
  summarise(
    pob_total = sum(pob),
    pob_0_14  = sum(pob[edad <= 14]),
    pob_15_59 = sum(pob[edad >= 15 & edad <= 59]),
    pob_15_64 = sum(pob[edad >= 15 & edad <= 64]),
    pob_60p   = sum(pob[edad >= 60]),
    pob_65p   = sum(pob[edad >= 65]),
    pob_60_79 = sum(pob[edad >= 60 & edad <= 79]),
    pob_80p   = sum(pob[edad >= 80]),
    edad_media_x   = sum(edad * pob) / sum(pob),
    edad_media_x05 = sum((edad + 0.5) * pob) / sum(pob),
    mediana_calc   = mediana_edad(edad, pob), .groups = "drop") |>
  mutate(psr65 = pob_15_64 / pob_65p,
         psr60 = pob_15_59 / pob_60p)
saveRDS(dane_ind, file.path(CFG$dir_clean, "dane_estructura_edad.rds"))

# Empalme de DOS versiones: 1950-2017 (marzo 2023) + 2018-2070 (julio 2025, base censo 2018).
# Un salto en 2017 -> 2018 sería un cambio de versión, no un fenómeno demográfico.
cat("\nEmpalme 2017 -> 2018 (cambio de archivo y de versión del DANE):\n")
ver(dane_ind |> arrange(anio) |>
      mutate(crec_pct = round(100 * (pob_total / dplyr::lag(pob_total) - 1), 3)) |>
      filter(anio %in% 2015:2020) |>
      transmute(anio, pob_total = round(pob_total), crec_pct,
                psr65 = round(psr65, 2), psr60 = round(psr60, 2),
                mediana_calc = round(mediana_calc, 2)))
cr_anual <- setNames(dane_ind$pob_total / dplyr::lag(dane_ind$pob_total) - 1, dane_ind$anio)
salto_pp <- unname(abs(cr_anual["2018"] - mean(cr_anual[c("2016", "2017")])))
verificar(isTRUE(salto_pp < 0.005),
          sprintf("Sin salto apreciable en el empalme (el crecimiento de 2018 difiere %.2f pp del de 2016-2017).",
                  100 * salto_pp),
          sprintf("Posible ruptura en el empalme 2017/2018 (diferencia de crecimiento: %.2f pp). Tratar 2018 como quiebre de serie y declararlo.",
                  100 * salto_pp), fatal = FALSE)


# ---- 5. Puntos de control: ¿la serie descargada es la versión post-COVID? ----
seccion("5. PUNTOS DE CONTROL DEL DANE (PDF, marzo 2023)")

# NOTA DE VERSIÓN (script 03b, hoja PPED): el Excel dice "Actualizado el 18 de Julio de 2025".
# Los puntos de control vienen del PDF de marzo de 2023. Es esperable que reproduzcan el
# tramo histórico pero NO el proyectado: son dos versiones distintas de la serie (D20).
# Estos controles validan la lectura del archivo, no la versión; registrar en FUENTES.md.
f_cp <- file.path(CFG$dir_externos, "documentacion", "checkpoints_dane.csv")
verificar(file.exists(f_cp), "Archivo de puntos de control encontrado.",
          paste("Falta", f_cp))
cp <- read.csv(f_cp, stringsAsFactors = FALSE, fileEncoding = "UTF-8") |> as_tibble()

calc <- dane_ind |>
  transmute(anio,
            pct_0_14 = 100 * pob_0_14 / pob_total,
            pct_15_59 = 100 * pob_15_59 / pob_total,
            pct_60p = 100 * pob_60p / pob_total,
            pct_60_79 = 100 * pob_60_79 / pob_total,
            pct_80p = 100 * pob_80p / pob_total,
            indice_envejecimiento = 100 * pob_60p / pob_0_14,
            edad_media = edad_media_x05, edad_media_alt = edad_media_x,
            pob_total = pob_total)

chk_cp <- cp |>
  filter(serie == "post", indicador %in% setdiff(names(calc), c("anio", "edad_media_alt"))) |>
  left_join(calc, by = c("anio")) |>
  rowwise() |>
  mutate(calculado = get(indicador),
         calculado_alt = if (indicador == "edad_media") edad_media_alt else NA_real_,
         dif = if (indicador == "edad_media") min(abs(calculado - valor), abs(calculado_alt - valor))
         else abs(calculado - valor),
         dif = if (tipo_tol == "rel") dif / valor else dif,
         ok = dif <= tolerancia) |>
  ungroup() |>
  select(indicador, anio, valor_pdf = valor, calculado, dif, tolerancia, ok) |>
  mutate(tramo = if_else(anio <= 2017, "1950-2017", "2018-2070"))

ver(chk_cp |> mutate(across(c(calculado, dif), ~ round(.x, 3))))
res_tramo <- chk_cp |> group_by(tramo) |>
  summarise(puntos = n(), ok = sum(ok, na.rm = TRUE), .groups = "drop")
ver(res_tramo)
# El PDF es de marzo de 2023: debe reproducir el tramo histórico (archivo 1950-2017, misma
# versión). En 2018-2070 el Excel es la actualización de julio de 2025: diferencias esperables.
h <- res_tramo[res_tramo$tramo == "1950-2017", ]
verificar(nrow(h) == 1 && h$ok == h$puntos,
          "El tramo histórico (versión marzo 2023) reproduce los puntos de control del PDF.",
          "El tramo histórico NO reproduce todos los puntos de control: revisar la lectura.",
          fatal = FALSE)
p2 <- res_tramo[res_tramo$tramo == "2018-2070", ]
if (nrow(p2) == 1) {
  cat(sprintf("  Tramo 2018-2070: %d de %d puntos coinciden con el PDF de 2023.\n", p2$ok, p2$puntos),
      "  Diferencias aquí son compatibles con la actualización de julio de 2025 (D20); no es un error de lectura.\n", sep = "")
}
write.csv(chk_cp, file.path(CFG$dir_tablas, "03_checkpoints_dane.csv"), row.names = FALSE)


# ---- 6. Comparación ONU frente a DANE: Colombia ------------------------------
seccion("6. COLOMBIA: ONU FRENTE A DANE")

comp <- un_col |>
  transmute(anio = Time, un_pob = pob_total * 1000, un_mediana = mediana_calc,
            un_pct_60p = 100 * pob_60p / pob_total, un_psr65 = psr65, un_psr60 = psr60) |>
  inner_join(dane_ind |> transmute(anio, dane_pob = pob_total, dane_mediana = mediana_calc,
                                   dane_pct_60p = 100 * pob_60p / pob_total,
                                   dane_psr65 = psr65, dane_psr60 = psr60), by = "anio") |>
  mutate(dif_pob_pct = round(100 * (dane_pob - un_pob) / un_pob, 2))

cat("Años comparables:", min(comp$anio), "-", max(comp$anio),
    "| fecha de la ONU:", BASE, "(DANE: 30 de junio)\n\n")
ver(comp |> filter(anio %in% c(1950, 1975, 2000, 2023, 2035, 2050, 2070)) |>
      mutate(across(where(is.numeric), ~ round(.x, 2))))

# Años de cruce de umbrales (D18): primer año con PSR bajo el umbral, 3 años seguidos
cruces <- bind_rows(lapply(CFG$psr_umbrales, function(u) {
  bind_rows(
    tibble(fuente = "ONU",  definicion = "15-64 / 65+", umbral = u,
           anio_cruce = anio_cruce(comp$anio, comp$un_psr65,   u)),
    tibble(fuente = "ONU",  definicion = "15-59 / 60+", umbral = u,
           anio_cruce = anio_cruce(comp$anio, comp$un_psr60,   u)),
    tibble(fuente = "DANE", definicion = "15-64 / 65+", umbral = u,
           anio_cruce = anio_cruce(comp$anio, comp$dane_psr65, u)),
    tibble(fuente = "DANE", definicion = "15-59 / 60+", umbral = u,
           anio_cruce = anio_cruce(comp$anio, comp$dane_psr60, u)))
}))
cat("\nAño de cruce (racha de", CFG$racha_cruce, "años; horizonte comparable hasta 2070):\n")
ver(cruces |> arrange(definicion, desc(umbral), fuente))
cat("\nNota: NA = no cruza el umbral dentro del horizonte comparable (hasta 2070).\n")


# ---- 7. Figura y salidas -----------------------------------------------------
seccion("7. FIGURA Y SALIDAS")

fig_dat <- comp |>
  select(anio, starts_with("un_psr"), starts_with("dane_psr")) |>
  pivot_longer(-anio, names_to = "serie", values_to = "psr") |>
  mutate(fuente = if_else(grepl("^un_", serie), "ONU (WPP 2024)", "DANE (post-COVID)"),
         definicion = if_else(grepl("65$", serie), "15-64 por cada persona de 65+",
                              "15-59 por cada persona de 60+"))

umbrales_dib <- tibble(umbral = c(3.0, 2.5))
col_fuentes <- c("ONU (WPP 2024)" = PAL$okabe_ito[["azul"]],
                 "DANE (post-COVID)" = PAL$okabe_ito[["verde"]])

p3 <- ggplot(fig_dat, aes(anio, psr, colour = fuente)) +
  capa_proyeccion(etiquetas = FALSE) +
  geom_hline(data = umbrales_dib, aes(yintercept = umbral),
             linetype = "dotted", colour = PAL$acento, linewidth = 0.6) +
  geom_line(linewidth = 1.15, lineend = "round") +
  facet_wrap(~ definicion) +
  scale_colour_manual(values = col_fuentes, name = NULL) +
  scale_x_continuous(breaks = seq(1950, 2070, 20), expand = expansion(mult = c(0.01, 0.02))) +
  scale_y_continuous(limits = c(0, NA), expand = expansion(mult = c(0, 0.06)),
                     labels = fmt_num(1)) +
  labs(title = "Soporte demográfico de Colombia: ONU frente a DANE",
       subtitle = paste0("Personas en edad de trabajar por cada persona mayor. ",
                         "Líneas punteadas: umbrales de referencia 3,0 y 2,5 (escenarios, no estándares).\n",
                         "Zona sombreada: proyección (desde 2024). El soporte demográfico no mide ",
                         "la sostenibilidad fiscal de un sistema pensional."),
       x = NULL, y = "Personas en edad de trabajar por persona mayor",
       caption = paste0("Fuentes: UN WPP 2024 (población por edad simple, fecha: ", BASE,
                        "); DANE, proyecciones nacionales ajustadas por COVID-19.")) +
  theme_dataquest()
print(p3)
guardar_fig(p3, "03_psr_colombia_onu_dane", ancho = 11, alto = 5.6)

write.csv(comp,   file.path(CFG$dir_tablas, "03_comparacion_onu_dane_colombia.csv"), row.names = FALSE)
write.csv(cruces, file.path(CFG$dir_tablas, "03_cruces_umbrales_colombia.csv"),      row.names = FALSE)
write.csv(cruces_paises, file.path(CFG$dir_tablas, "03_cruces_umbrales_paises_onu.csv"), row.names = FALSE)

cat("\nRecordatorio: registra en data/raw/externos/FUENTES.md los archivos usados\n",
    "(URL, fecha de descarga, licencia, transformaciones) y el PDF del DANE como documentación.\n", sep = "")

# dbDisconnect(con, shutdown = TRUE)