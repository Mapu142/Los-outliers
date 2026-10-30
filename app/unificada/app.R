#==============================================================================
# app/unificada/app_unificada.R
# Punto de entrada de la app unificada.
# Ejecutar desde la raíz del proyecto:
#   shiny::runApp("app/unificada")
#==============================================================================

#---- Módulo PCA / estadios ---------------------------------------------------
# Se busca el archivo junto a la app o desde la raíz del proyecto.
ruta_mod_pca <- c("mod_pca_clusters.R", "app/unificada/modules/mod_pca_clusters.R")
ruta_mod_pca <- ruta_mod_pca[file.exists(ruta_mod_pca)][1]
if (is.na(ruta_mod_pca)) stop("No se encontró mod_pca_clusters.R junto a la app.")
source(ruta_mod_pca, encoding = "UTF-8")

# Si falla la carga, la app sigue abierta y las pestañas muestran un aviso;
# el motivo queda escrito en la consola de R.
DATOS_PCA <- tryCatch(
  cargar_datos_pca(),
  error = function(e) {
    message("[PCA] No se pudo cargar el módulo de arquetipos: ", conditionMessage(e))
    NULL
  }
)

aviso_pca <- box(
  title = "Resultados del PCA no disponibles", width = 12, status = "danger",
  tags$p("No se pudieron cargar los archivos del PCA y los clústeres.",
         "El detalle está en la consola de R.")
)

#---- UI ----------------------------------------------------------------------
ui <- dashboardPage(
  title       = "Trayectorias del Envejecimiento Global · DataQuest 2026",
  dark        = FALSE,
  fullscreen  = TRUE,
  scrollToTop = TRUE,
  
  header = dashboardHeader(
    title = dashboardBrand(title = "WPP 2024 · Unificada", color = "primary"),
    status = "white",
    rightUi = tags$li(
      class = "dropdown",
      tags$span(
        style = "padding:8px 14px; color:#64748b; font-size:13px;",
        "ASA DataQuest 2026 · 30-oct-2026"
      )
    )
  ),
  
  sidebar = dashboardSidebar(
    skin = "light",
    status = "primary",
    elevation = 3,
    sidebarMenu(
      id = "menu",
      menuItem("Inicio",            tabName = "inicio",        icon = icon("house")),
      menuItem("Explorador series", tabName = "series",        icon = icon("chart-line")),
      menuItem("Arquetipos (PCA)",  tabName = "pca",           icon = icon("diagram-project")),
      menuItem("Transiciones",      tabName = "transiciones",  icon = icon("right-left")),
      menuItem("Discrepancias ONU", tabName = "discrepancias", icon = icon("scale-balanced")),
      menuItem("Puntos críticos",   tabName = "criticos",      icon = icon("triangle-exclamation")),
      menuItem("Mapa mundial",      tabName = "mapa",          icon = icon("earth-americas")),
      menuItem("Validación",        tabName = "validacion",    icon = icon("flask"))
    ),
    
    # Filtros globales
    tags$div(
      class = "sidebar-var",
      tags$hr(),
      h5("Filtros globales", style = "color:#fff; margin-bottom:8px;"),
      selectizeInput("g_paises", "Países (hasta 8)",
                     choices  = setNames(DATOS_APP$nombres$ISO3_code,
                                         paste0(DATOS_APP$nombres$Location,
                                                " (", DATOS_APP$nombres$ISO3_code, ")")),
                     selected = c("COL", "CHN", "USA"),
                     multiple = TRUE,
                     options  = list(maxItems = 8, placeholder = "Escribe para buscar...")),
      selectInput("g_variable", "Indicador",
                  choices  = setNames(VARS_DISP, ETIQ_VAR[VARS_DISP]),
                  selected = "MedianAgePop"),
      sliderInput("g_anios", "Rango de años",
                  min = 1950, max = ANIO_MAX,
                  value = c(1950, ANIO_MAX), step = 1, sep = "")
    )
  ),
  
  body = dashboardBody(
    useShinyjs(),
    tags$head(
      tags$link(rel = "stylesheet", type = "text/css", href = "custom.css")
    ),
    tabItems(
      #--- 1. Inicio ---
      tabItem(
        tabName = "inicio",
        fluidRow(
          valueBox(value = length(unique(DATOS_APP$ts_largo$ISO3_code)),
                   subtitle = "Países analizados",
                   icon = icon("globe"), color = "primary", width = 3),
          valueBox(value = ANIO_MAX,
                   subtitle = "Horizonte de proyección",
                   icon = icon("calendar-days"), color = "info", width = 3),
          valueBox(value = "K = 4",
                   subtitle = "Arquetipos demográficos",
                   icon = icon("layer-group"), color = "success", width = 3),
          valueBox(value = "7 variables",
                   subtitle = "Pronosticadas con 3 métodos",
                   icon = icon("chart-simple"), color = "warning", width = 3)
        ),
        fluidRow(
          box(
            title = "¿Qué muestra esta app?",
            width = 7, status = "primary",
            tags$p("Compara las proyecciones demográficas propias con la variante ",
                   tags$b("Medium"), " de la ONU (WPP 2024) hasta 2100, ",
                   "y las articula con un PCA longitudinal de 161 países."),
            tags$ul(
              tags$li(tags$b("Explorador:"), " series históricas y proyectadas con IC95."),
              tags$li(tags$b("Arquetipos:"), " PCA + K=4 estadios demográficos."),
              tags$li(tags$b("Transiciones:"), " cuándo y cómo los países cambian de estadio."),
              tags$li(tags$b("Discrepancias:"), " dónde nuestro modelo se separa de la ONU."),
              tags$li(tags$b("Puntos críticos:"), " año en que la relación de soporte cae bajo el umbral."),
              tags$li(tags$b("Mapa:"), " animación año a año de cualquier indicador."),
              tags$li(tags$b("Validación:"), " backtesting 1990/2000/2010.")
            )
          ),
          box(
            title = "Cómo leer los gráficos",
            width = 5, status = "info",
            tags$ul(
              tags$li(tags$span(style = "color:#0072B2;", "■"), " Azul = estimación (≤ 2023)"),
              tags$li(tags$span(style = "color:#E69F00;", "■"), " Naranja = proyección"),
              tags$li(tags$span(style = "color:#D55E00;", "■"), " Bermellón = acento / referencia"),
              tags$li("Línea continua gruesa: histórico observado."),
              tags$li("Línea continua naranja: pronóstico propio."),
              tags$li("Línea discontinua: ONU Medium."),
              tags$li("Banda sombreada: IC 95% empírico del backtesting.")
            ),
            tags$p(class = "leyenda-lineas",
                   "Los filtros del sidebar (países, indicador, años) afectan a las pestañas ",
                   "Explorador, Discrepancias, Puntos críticos y Validación.")
          )
        )
      ),
      
      #--- 2. Explorador de series --------------------------------------------------
      tabItem(
        tabName = "series",
        mod_series_ui("series")
      ),
      
      #--- 3. Arquetipos PCA ---
      tabItem(tabName = "pca",
              if (is.null(DATOS_PCA)) aviso_pca else mod_pca_ui("pca")),
      
      #--- 4. Transiciones ---
      tabItem(tabName = "transiciones",
              if (is.null(DATOS_PCA)) aviso_pca else mod_transiciones_ui("pca")),
      
      #--- 5. Discrepancias ---
      tabItem(tabName = "discrepancias", mod_disc_ui("disc")),
      
      #--- 6. Puntos críticos ---
      tabItem(tabName = "criticos", mod_criticos_ui("crit")),
      
      #--- 7. Mapa mundial ---
      tabItem(tabName = "mapa",
              box(title = "Mapa mundial animado", width = 12, status = "primary",
                  tags$p("Próximo paso: combinar mapa de ", tags$code("app_ts.R"),
                         " con LISA del script 06."))),
      
      #--- 8. Validación ---
      tabItem(tabName = "validacion",
              box(title = "Validación de modelos (backtesting)", width = 12, status = "primary",
                  tags$p("Próximo paso: migrar la pestaña de validación de ", tags$code("app_ts.R"))))
    )
  ),
  
  footer = dashboardFooter(
    left  = "ASA DataQuest 2026 · Los Outliers",
    right = "Fuente: UN WPP 2024 (Medium) · DANE · Natural Earth"
  )
)

#---- Server ------------------------------------------------------------------
server <- function(input, output, session) {
  
  observe({
    message("Filtros globales: ",
            length(input$g_paises), " países, ",
            input$g_variable, ", ",
            input$g_anios[1], "-", input$g_anios[2])
  })
  
  # Conectar el módulo de series pasando input directamente
  mod_series_server("series", DATOS_APP, main_input = input)
  
  # en server <- function(...), junto a mod_series_server:
  mod_disc_server("disc",      DATOS_APP, main_input = input)
  mod_criticos_server("crit",  DATOS_APP, main_input = input)
  
  # Módulo PCA / estadios: alimenta las pestañas "Arquetipos (PCA)" y "Transiciones"
  if (!is.null(DATOS_PCA)) mod_pca_server("pca", datos = DATOS_PCA)
}

#---- Lanzar app --------------------------------------------------------------
shinyApp(ui, server)