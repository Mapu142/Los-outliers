# ==============================================================================
# R/utils_datos.R
# Utilidades de datos: rutas, consola, verificaciones y helpers SQL (duckdb)
# Requiere: R/config.R cargado antes (usa CFG).
# ==============================================================================

# ---- Regla de países (D1) ----------------------------------------------------
# Un registro es "país/área" si y solo si tiene ISO3_code no nulo ni vacío.
# NO usar LocTypeName: 234 ubicaciones lo tienen en NA.
SQL_ES_PAIS <- "ISO3_code IS NOT NULL AND TRIM(ISO3_code) <> ''"

# ---- Rutas -------------------------------------------------------------------
ruta <- function(archivo, dir = CFG$dir_raw) {
  normalizePath(file.path(dir, archivo), mustWork = TRUE)
}

# ---- Consola -----------------------------------------------------------------
# Encabezado de sección
seccion <- function(txt) {
  cat("\n", strrep("=", 70), "\n", txt, "\n", strrep("=", 70), "\n", sep = "")
}

# Imprime un data.frame completo como tibble (evita print(x, n = Inf) sobre
# data.frame base, que produce "invalid 'na.print' specification")
ver <- function(x) print(tibble::as_tibble(x), n = Inf)

# Verificación con mensaje claro. fatal = TRUE detiene el script si falla.
verificar <- function(condicion, ok, error, fatal = TRUE) {
  if (isTRUE(condicion)) {
    cat("  [OK]    ", ok, "\n", sep = "")
    return(invisible(TRUE))
  }
  msg <- paste0("  [FALLA] ", error)
  if (fatal) stop(msg, call. = FALSE)
  cat(msg, "\n", sep = "")
  warning(error, call. = FALSE)
  invisible(FALSE)
}

# ---- Helpers SQL -------------------------------------------------------------
# Genera "SUM(CASE WHEN col IS NULL ...) AS col" para una lista de columnas
sql_contar_nulos <- function(cols) {
  paste0(sprintf('SUM(CASE WHEN "%s" IS NULL THEN 1 ELSE 0 END) AS "%s"', cols, cols),
         collapse = ",\n  ")
}

sql_contar_no_nulos <- function(cols) {
  paste0(sprintf('SUM(CASE WHEN "%s" IS NOT NULL THEN 1 ELSE 0 END) AS "%s"', cols, cols),
         collapse = ",\n  ")
}

# ---- duckdb ------------------------------------------------------------------
# Abre una conexión en memoria (cierra la anterior si existe, para poder
# re-ejecutar el script desde arriba sin conexiones huérfanas)
conectar_duckdb <- function(con_previa = NULL) {
  if (!is.null(con_previa) && DBI::dbIsValid(con_previa)) {
    DBI::dbDisconnect(con_previa, shutdown = TRUE)
  }
  DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
}

# Crea una vista que lee un CSV/CSV.GZ bajo demanda (no carga nada en RAM)
crear_vista_csv <- function(con, nombre_vista, archivo) {
  DBI::dbExecute(con, glue::glue("
    CREATE OR REPLACE VIEW {nombre_vista} AS
    SELECT * FROM read_csv_auto('{ruta(archivo)}', header = TRUE, sample_size = -1)"))
  invisible(nombre_vista)
}
