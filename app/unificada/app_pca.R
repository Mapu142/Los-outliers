# ==============================================================================
# app_pca.R
# App independiente para probar el módulo de PCA y estadios demográficos.
#
# Ejecutar desde RStudio, con el proyecto (.Rproj) abierto:
#   shiny::runApp("app_pca.R")
#
# Requisitos previos:
#   - Haber corrido R/02_pca_y_clustering.R (genera los parquet y los CSV).
#   - Paquetes: shiny, dplyr, tidyr, ggplot2, ggrepel, DT, arrow.
# ==============================================================================

if (!file.exists("R/config.R")) stop("Ejecute la app desde la raíz del proyecto (.Rproj).")

source("R/config.R",           encoding = "UTF-8")
source("R/utils_datos.R",      encoding = "UTF-8")
source("R/tema.R",             encoding = "UTF-8")
source("R/mod_pca_clusters.R", encoding = "UTF-8")

datos_pca <- cargar_datos_pca()

ui <- fluidPage(
  titlePanel("Trayectorias Fisiológicas del Futuro Global: PCA y estadios demográficos"),
  mod_pca_ui("pca")
)

server <- function(input, output, session) {
  mod_pca_server("pca", datos = datos_pca)
}

shinyApp(ui, server)
