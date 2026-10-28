# ==============================================================================
# R/config.R
# Configuración global del proyecto ASA DataQuest 2026 · WPP 2024
# ------------------------------------------------------------------------------
# ÚNICO lugar donde se tocan rutas, años de corte, tolerancias y semillas.
# Se carga con:  source("R/config.R", encoding = "UTF-8")
# Requiere que el directorio de trabajo sea la raíz del proyecto (.Rproj).
# ==============================================================================

CFG <- list(
  
  # ---- Rutas (relativas a la raíz del proyecto) -------------------------------
  dir_raw    = "data/raw",
  dir_clean  = "data/clean",
  dir_figs   = "output/figuras",
  dir_tablas = "output/tablas",
  dir_externos = "data/raw/externos",   # fuentes externas (D13) + FUENTES.md
  
  # ---- Archivos de entrada ----------------------------------------------------
  f_medium = "WPP2024_Demographic_Indicators_Medium_csv.gz",
  f_other  = "WPP2024_Demographic_Indicators_OtherVariants_csv.gz",
  f_notes  = "WPP2024_Demographic_Indicators_notes.csv",
  f_suppl  = "WPP2024_Supplement_Births_and_LE60.csv",
  
  # ---- Archivos de salida de la Fase 0 ----------------------------------------
  f_parquet = "wpp_paises_medium_suppl.parquet",
  f_dicc    = "diccionario_indicadores.rds",
  
  # ---- Convenciones temporales (D2, D3) ---------------------------------------
  primer_anio          = 1950L,
  ultimo_anio_estimado = 2023L,   # Time <= 2023: estimaciones; >= 2024: proyecciones
  ultimo_anio_analisis = 2100L,   # 2101 solo trae TPopulation1Jan (D3)
  
  # ---- Tolerancias y umbrales -------------------------------------------------
  tol_births      = 0.0011,  # 0.001 documentado + margen de punto flotante (D7)
  umbral_doubling = 0.5,     # DoublingTime solo existe con crecimiento > 0.5 % (D6)
  tfr_reemplazo   = 2.1,     # nivel de reemplazo generacional
  
  # ---- Soporte demográfico (D18) ----------------------------------------------
  psr_umbrales = c(4, 3, 2.5, 2),  # umbrales de referencia: ESCENARIOS, no estándares
  racha_cruce  = 3L,               # años seguidos bajo el umbral para declarar el cruce
  umbral_universo_miles = 1000L,   # universo de análisis: población >= 1 millón (D12)
  
  # ---- Reproducibilidad -------------------------------------------------------
  semilla = 2026L,
  
  # ---- Formato numérico de figuras y tablas (cambiar aquí si el reporte final
  #      se redacta en inglés: sep_decimal = ".", sep_miles = ",") ---------------
  sep_decimal = ",",
  sep_miles   = ".",
  fig_dpi     = 300
)

# Crea las carpetas de salida si no existen (idempotente)
crear_directorios <- function() {
  for (d in c(CFG$dir_clean, CFG$dir_figs, CFG$dir_tablas)) {
    dir.create(d, showWarnings = FALSE, recursive = TRUE)
  }
  invisible(TRUE)
}