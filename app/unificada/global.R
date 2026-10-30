#==============================================================================
# app/unificada/global.R
# Carga ÚNICA de datos y funciones compartidas para la app unificada.
# Se ejecuta UNA VEZ al arrancar la app (antes de cualquier usuario).
#==============================================================================

#---- 0. Paquetes -------------------------------------------------------------
paquetes <- c("shiny", "bs4Dash", "dplyr", "tidyr", "ggplot2", "plotly",
              "DT", "readr", "arrow", "sf", "sf", "scales", "glue",
              "ggrepel", "shinyjs")
faltan <- setdiff(paquetes, rownames(installed.packages()))
if (length(faltan) > 0) install.packages(faltan)
invisible(lapply(paquetes, library, character.only = TRUE))

#---- 1. Configuración del proyecto ------------------------------------------
# La app se ejecuta desde la raíz del proyecto (.Rproj abierto)
if (!file.exists("R/config.R")) {
  stop("Abre el proyecto (.Rproj) o fija setwd() en la raíz.")
}
source("R/config.R",   encoding = "UTF-8")
source("R/utils_datos.R", encoding = "UTF-8")
source("R/tema.R",     encoding = "UTF-8")

#---- 2. Rutas a los archivos de entrada -------------------------------------
# Series de tiempo (script 10 + 11)
DIR_TABLAS <- CFG$dir_tablas
DIR_CLEAN  <- CFG$dir_clean

f <- list(
  # --- Series de tiempo ---
  largo        = file.path(DIR_TABLAS, "10_Proyecciones_Propias_vs_ONU_largo.csv"),
  hist         = file.path(DIR_TABLAS, "10_historico_largo.csv"),
  valid        = file.path(DIR_TABLAS, "10_validacion_por_pais.csv"),
  criticos     = file.path(DIR_TABLAS, "10_puntos_criticos_RS.csv"),
  d16          = file.path(DIR_TABLAS, "11_d16_posicion_vs_banda80.csv"),
  triang       = file.path(DIR_TABLAS, "11_triangulacion_colombia_rs3.csv"),
  resumen_disc = file.path(DIR_TABLAS, "10_resumen_discrepancia.csv"),
  # --- PCA y arquetipos ---
  pca_coord    = file.path(DIR_CLEAN,  "wpp_pca_coordenadas_todo_periodo.parquet"),
  pca_arq      = file.path(DIR_CLEAN,  "wpp_matriz_arquetipos_proyecciones.parquet"),
  pca_trans    = file.path(DIR_CLEAN,  "wpp_transiciones_persistentes_globales.parquet"),
  pca_eig      = file.path(DIR_TABLAS, "02_pca_autovalores.csv"),
  pca_vars     = file.path(DIR_TABLAS, "02_pca_calidad_variables.csv"),
  pca_cent     = file.path(DIR_TABLAS, "02_cluster_centroides.csv"),
  # --- Espacial ---
  mundo_geom   = file.path(DIR_CLEAN,  "mundo_geom.rds"),
  lisa         = file.path(DIR_TABLAS, "06_lisa_resultados.csv"),
  # --- DANE ---
  dane         = file.path(DIR_CLEAN,  "dane_estructura_edad.rds")
)

# Verificación: todos los archivos deben existir
f_vec <- unlist(f)
faltan_archivos <- f_vec[!file.exists(f_vec)]

if (length(faltan_archivos) > 0) {
  stop("Faltan archivos para la app unificada:\n  ",
       paste(basename(faltan_archivos), collapse = "\n  "),
       "\nEjecuta primero los scripts 00-11 y 02_PCA.", call. = FALSE)
}

#---- 3. Carga de datos (una sola vez) ---------------------------------------
message("Cargando datos de la app unificada...")

# --- Series de tiempo ---
ts_largo   <- readr::read_csv(f$largo,    show_col_types = FALSE)
ts_hist    <- readr::read_csv(f$hist,     show_col_types = FALSE)
ts_valid   <- readr::read_csv(f$valid,    show_col_types = FALSE)
ts_crit    <- readr::read_csv(f$criticos, show_col_types = FALSE)
ts_d16     <- readr::read_csv(f$d16,      show_col_types = FALSE)
ts_triang  <- readr::read_csv(f$triang,   show_col_types = FALSE)
ts_disc    <- readr::read_csv(f$resumen_disc, show_col_types = FALSE)

# --- PCA ---
pca_coord  <- as.data.frame(arrow::read_parquet(f$pca_coord))
pca_arq    <- as.data.frame(arrow::read_parquet(f$pca_arq))
pca_trans  <- as.data.frame(arrow::read_parquet(f$pca_trans))
pca_eig    <- read.csv(f$pca_eig)
pca_vars   <- read.csv(f$pca_vars)
pca_cent   <- read.csv(f$pca_cent, check.names = FALSE)
names(pca_cent)[1] <- "Arquetipo"

# --- Espacial ---
mundo_geom <- readRDS(f$mundo_geom)
lisa_tab   <- readr::read_csv(f$lisa, show_col_types = FALSE)

# --- DANE ---
dane_ind   <- readRDS(f$dane)

message("  ✓ Series de tiempo: ", format(nrow(ts_largo), big.mark = ","), " filas")
message("  ✓ PCA: ", nrow(pca_coord), " país-años")
message("  ✓ Geometrías: ", nrow(mundo_geom), " países")

#---- 4. Tabla maestra de nombres de países ----------------------------------
nombres_paises <- ts_hist |>
  dplyr::distinct(ISO3_code, Location) |>
  dplyr::arrange(Location)

#---- 5. Constantes y etiquetas ----------------------------------------------
ETIQ_VAR <- c(
  MedianAgePop = "Edad mediana (años)",
  TFR          = "Tasa global de fecundidad (hijos por mujer)",
  LEx          = "Esperanza de vida al nacer (años)",
  LE60         = "Esperanza de vida a los 60 (años)",
  LE65         = "Esperanza de vida a los 65 (años)",
  CBR          = "Natalidad bruta (por mil)",
  IRG          = "Índice vital (nacim./defunc.)",
  RS           = "Relación de soporte (15-64 / 65+)"
)

VARS_DISP <- intersect(names(ETIQ_VAR), unique(ts_largo$Variable))

ANIO_MIN  <- min(ts_largo$Time)
ANIO_MAX  <- max(ts_largo$Time)
ANIO_CORTE <- 2023L  # último año de estimación

# Paleta de Okabe-Ito (ya en PAL$okabe_ito de tema.R)
COL_SERIES <- unname(PAL$okabe_ito[c("azul", "bermellon", "verde",
                                     "naranja", "purpura", "celeste",
                                     "negro", "amarillo")])

#---- 6. Módulo del PCA (ya existe) ------------------------------------------
source("R/mod_pca_clusters.R", encoding = "UTF-8")

#---- 7. Lista de datos para pasar al server ---------------------------------
DATOS_APP <- list(
  # Series
  ts_largo   = ts_largo,
  ts_hist    = ts_hist,
  ts_valid   = ts_valid,
  ts_crit    = ts_crit,
  ts_d16     = ts_d16,
  ts_triang  = ts_triang,
  ts_disc    = ts_disc,
  # PCA
  pca_coord  = pca_coord,
  pca_arq    = pca_arq,
  pca_trans  = pca_trans,
  pca_eig    = pca_eig,
  pca_vars   = pca_vars,
  pca_cent   = pca_cent,
  # Espacial
  mundo_geom = mundo_geom,
  lisa_tab   = lisa_tab,
  # DANE
  dane_ind   = dane_ind,
  # Nombres
  nombres    = nombres_paises
)

message("✓ App unificada lista para arrancar.")