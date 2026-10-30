#==============================================================================
# app/unificada/global.R
# Carga ÚNICA de datos y funciones compartidas para la app unificada.
# Se ejecuta UNA VEZ al arrancar la app.
#==============================================================================

#---- 0. Paquetes -------------------------------------------------------------
paquetes <- c("shiny", "bs4Dash", "dplyr", "tidyr", "ggplot2", "plotly",
              "DT", "readr", "arrow", "sf", "scales", "glue",
              "ggrepel", "shinyjs")
faltan <- setdiff(paquetes, rownames(installed.packages()))
if (length(faltan) > 0) install.packages(faltan)
invisible(lapply(paquetes, library, character.only = TRUE))

#---- 1. Raíz del proyecto -----------------------------------------------------
# shiny::runApp("app/unificada") cambia el directorio de trabajo a la carpeta
# de la app, así que "R/config.R" no se encontraría. Se sube hasta hallar la raíz.
.buscar_raiz <- function() {
  d <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  for (i in 1:5) {
    if (file.exists(file.path(d, "R", "config.R"))) return(d)
    d <- dirname(d)
  }
  stop("No encuentro la raíz del proyecto (carpeta con R/config.R). ",
       "Abre el .Rproj y ejecuta shiny::runApp('app/unificada').", call. = FALSE)
}
RAIZ <- .buscar_raiz()
setwd(RAIZ)   # a partir de aquí todas las rutas relativas parten de la raíz

source("R/config.R",      encoding = "UTF-8")
source("R/utils_datos.R", encoding = "UTF-8")
source("R/tema.R",        encoding = "UTF-8")

#---- 2. Rutas a los archivos de entrada -------------------------------------
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

# Obligatorios para que la app arranque HOY (series + PCA).
# El resto es opcional: si falta, queda en NULL y solo avisa en la consola.
OBLIGATORIOS <- c("largo", "hist", "pca_coord", "pca_arq",
                  "pca_eig", "pca_vars", "pca_cent")

f_vec <- unlist(f)
faltan_obl <- f_vec[names(f_vec) %in% OBLIGATORIOS & !file.exists(f_vec)]
if (length(faltan_obl) > 0) {
  stop("Faltan archivos obligatorios para la app:\n  ",
       paste(faltan_obl, collapse = "\n  "),
       "\nRevisa los nombres/rutas en la sección 2 de global.R ",
       "o ejecuta antes los scripts que los generan.", call. = FALSE)
}
faltan_opc <- f_vec[!names(f_vec) %in% OBLIGATORIOS & !file.exists(f_vec)]
if (length(faltan_opc) > 0) {
  message("Aviso: archivos opcionales no encontrados (esas pestañas quedarán sin datos):\n  ",
          paste(basename(faltan_opc), collapse = "\n  "))
}

leer_csv_op <- function(p) if (file.exists(p)) readr::read_csv(p, show_col_types = FALSE) else NULL
leer_pq_op  <- function(p) if (file.exists(p)) as.data.frame(arrow::read_parquet(p)) else NULL
leer_rds_op <- function(p) if (file.exists(p)) readRDS(p) else NULL

#---- 3. Carga de datos (una sola vez) ---------------------------------------
message("Cargando datos de la app unificada...")

# --- Series de tiempo ---
ts_largo  <- readr::read_csv(f$largo, show_col_types = FALSE)
ts_hist   <- readr::read_csv(f$hist,  show_col_types = FALSE)
ts_valid  <- leer_csv_op(f$valid)
ts_crit   <- leer_csv_op(f$criticos)
ts_d16    <- leer_csv_op(f$d16)
ts_triang <- leer_csv_op(f$triang)
ts_disc   <- leer_csv_op(f$resumen_disc)

# --- PCA ---
pca_coord <- as.data.frame(arrow::read_parquet(f$pca_coord))
pca_arq   <- as.data.frame(arrow::read_parquet(f$pca_arq))
pca_trans <- leer_pq_op(f$pca_trans)
pca_eig   <- read.csv(f$pca_eig)
pca_vars  <- read.csv(f$pca_vars)
pca_cent  <- read.csv(f$pca_cent, check.names = FALSE)
names(pca_cent)[1] <- "Arquetipo"

# --- Espacial y DANE ---
mundo_geom <- leer_rds_op(f$mundo_geom)
lisa_tab   <- leer_csv_op(f$lisa)
dane_ind   <- leer_rds_op(f$dane)

message("  OK Series de tiempo: ", format(nrow(ts_largo), big.mark = ","), " filas")
message("  OK PCA: ", nrow(pca_coord), " país-años")
if (!is.null(mundo_geom)) message("  OK Geometrías: ", nrow(mundo_geom), " países")

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

ANIO_MIN   <- min(ts_hist$Time)
ANIO_MAX   <- max(ts_largo$Time)
ANIO_CORTE <- 2023L  # último año de estimación

# Paleta Okabe-Ito (de tema.R) con respaldo por si cambian los nombres
COL_SERIES <- tryCatch(
  unname(PAL$okabe_ito[c("azul", "bermellon", "verde", "naranja",
                         "purpura", "celeste", "negro", "amarillo")]),
  error = function(e) NULL
)
if (is.null(COL_SERIES) || anyNA(COL_SERIES)) {
  COL_SERIES <- c("#0072B2", "#D55E00", "#009E73", "#E69F00",
                  "#CC79A7", "#56B4E9", "#000000", "#F0E442")
}

#---- 6. Módulos --------------------------------------------------------------
source("app/unificada/modules/mod_pca_clusters.R",               encoding = "UTF-8")
source("app/unificada/modules/mod_series.R", encoding = "UTF-8")

#---- 7. Lista de datos para pasar al server ---------------------------------
DATOS_APP <- list(
  ts_largo = ts_largo, ts_hist = ts_hist, ts_valid = ts_valid,
  ts_crit = ts_crit, ts_d16 = ts_d16, ts_triang = ts_triang, ts_disc = ts_disc,
  pca_coord = pca_coord, pca_arq = pca_arq, pca_trans = pca_trans,
  pca_eig = pca_eig, pca_vars = pca_vars, pca_cent = pca_cent,
  mundo_geom = mundo_geom, lisa_tab = lisa_tab, dane_ind = dane_ind,
  nombres = nombres_paises
)

message("App unificada lista para arrancar.")