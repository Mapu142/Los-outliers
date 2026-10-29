# =========================================================================
# TRAYECTORIAS DEL ENVEJECIMIENTO GLOBAL (2024-2100)
# Dashboard interactivo - DataQuest 2026 - Competencia Estadística
# =========================================================================

library(shiny)
library(bs4Dash)
library(dplyr)
library(tidyr)
library(plotly)
library(readr)
library(DT)

# 1. Datos ----------------------------------------------------------------

f_largo   <- "04_Proyecciones_Propias_vs_ONU_largo.csv"
DIR_DATOS <- Filter(function(d) file.exists(file.path(d, f_largo)),
                    c("output/tablas", "../output/tablas", "."))
if (length(DIR_DATOS) == 0) {
  stop("No se encuentra '", f_largo, "' en output/tablas ni junto a app.R. ",
       "Ejecuta primero el script 01 de proyecciones.")
}
DIR_DATOS <- DIR_DATOS[1]
leer_opcional <- function(f) {
  p <- file.path(DIR_DATOS, f)
  if (file.exists(p)) read_csv(p, show_col_types = FALSE) else NULL
}
largo    <- read_csv(file.path(DIR_DATOS, f_largo), show_col_types = FALSE)
hist_l   <- leer_opcional("04_historico_largo.csv")
valid    <- leer_opcional("04_validacion_por_pais.csv")
clusters <- leer_opcional("04_clusters.csv")
if (!is.null(clusters) && !all(c("ISO3_code", "Cluster") %in% names(clusters))) clusters <- NULL

if (!"ONU_en_IC95" %in% names(largo)) {
  largo$ONU_en_IC95 <- largo$ONU >= largo$lo95 & largo$ONU <= largo$hi95
}

ETIQ <- c(
  MedianAgePop = "Edad mediana (años)",
  TFR          = "Tasa global de fecundidad (hijos por mujer)",
  LEx          = "Esperanza de vida al nacer (años)",
  LE60         = "Esperanza de vida a los 60 años",
  CBR          = "Natalidad bruta (por mil)",
  IRG          = "Índice de reemplazo generacional (nacimientos / muertes)",
  RS           = "Relación de soporte (15-64 / 65+)"
)
vars_disp     <- intersect(names(ETIQ), unique(largo$Variable))
choices_vars  <- setNames(vars_disp, ETIQ[vars_disp])
ANIO_MAX      <- max(largo$Time)
ANIO_HIST     <- min(largo$Time) - 1
TIENE_RS      <- "RS" %in% vars_disp

# Nombres de países
nombres_raw <- if (!is.null(hist_l) && "Location" %in% names(hist_l)) {
  hist_l %>% distinct(ISO3_code, Location)
} else tibble(ISO3_code = character(), Location = character())

nombres <- tibble(ISO3_code = sort(unique(largo$ISO3_code))) %>%
  left_join(nombres_raw, by = "ISO3_code") %>%
  mutate(Location = coalesce(Location, ISO3_code)) %>%
  arrange(Location)

nombre_de <- function(iso) {
  out <- nombres$Location[match(iso, nombres$ISO3_code)]
  out[iso == "MUNDO"] <- "Promedio de países"
  out
}
choices_paises <- setNames(nombres$ISO3_code, paste0(nombres$Location, " (", nombres$ISO3_code, ")"))

# Promedio simple de países (referencia mundial)
mundo_fut <- largo %>%
  group_by(Variable, Time) %>%
  summarise(Propia = mean(Propia, na.rm = TRUE), ONU = mean(ONU, na.rm = TRUE), .groups = "drop")
mundo_hist <- if (!is.null(hist_l)) {
  hist_l %>% group_by(Variable, Time) %>% summarise(Valor = mean(Valor, na.rm = TRUE), .groups = "drop")
} else NULL

# 2. Utilidades -----------------------------------------------------------

colores  <- c("#2563eb", "#dc2626", "#16a34a", "#9333ea", "#ea580c", "#0891b2", "#be185d", "#65a30d")
COL_MUND <- "#475569"

con_alpha <- function(hex, a = 0.15) {
  r <- grDevices::col2rgb(hex)
  sprintf("rgba(%d,%d,%d,%.2f)", r[1], r[2], r[3], a)
}
fmt   <- function(x, d = 2) ifelse(is.na(x), "—", formatC(x, format = "f", digits = d))
pull1 <- function(x) if (length(x)) x[1] else NA_real_

# Primer año desde el cual la serie SE MANTIENE por debajo del umbral
anio_critico <- function(t, rs, umbral) {
  ok <- rs < umbral
  if (all(is.na(ok))) return(NA_real_)
  if (all(ok))        return(min(t))
  if (!tail(ok, 1))   return(NA_real_)
  max(t[!ok]) + 1
}

datos_ent <- function(e, v) {
  if (e == "MUNDO") {
    list(
      fut  = mundo_fut %>% filter(Variable == v) %>% arrange(Time),
      hist = if (!is.null(mundo_hist)) mundo_hist %>% filter(Variable == v) %>% arrange(Time) else NULL
    )
  } else {
    list(
      fut  = largo %>% filter(ISO3_code == e, Variable == v) %>% arrange(Time),
      hist = if (!is.null(hist_l)) hist_l %>% filter(ISO3_code == e, Variable == v) %>% arrange(Time) else NULL
    )
  }
}

# Dibuja una entidad (país o promedio): observado + propio (con IC95) + ONU
trazar_entidad <- function(p, e, v, col, mod = "Ambos", ver_hist = TRUE, ver_ic = TRUE) {
  nm <- nombre_de(e); d <- datos_ent(e, v); leyenda <- TRUE
  
  if (ver_hist && !is.null(d$hist) && nrow(d$hist) > 0) {
    p <- p %>% add_trace(
      type = "scatter", mode = "lines", x = d$hist$Time, y = d$hist$Valor,
      name = nm, legendgroup = e, showlegend = leyenda,
      line = list(color = col, width = 2.5),
      hovertemplate = paste0(nm, " · observado: %{y:.2f}<extra></extra>")
    )
    leyenda <- FALSE
  }
  if (mod %in% c("Propia", "Ambos") && nrow(d$fut) > 0) {
    if (ver_ic && e != "MUNDO" && all(c("lo95", "hi95") %in% names(d$fut))) {
      t <- d$fut$Time
      p <- p %>% add_trace(
        type = "scatter", mode = "lines", x = c(t, rev(t)), y = c(d$fut$hi95, rev(d$fut$lo95)),
        fill = "toself", fillcolor = con_alpha(col, 0.15), line = list(width = 0),
        legendgroup = e, showlegend = FALSE, hoverinfo = "skip"
      )
    }
    p <- p %>% add_trace(
      type = "scatter", mode = "lines", x = d$fut$Time, y = d$fut$Propia,
      name = nm, legendgroup = e, showlegend = leyenda,
      line = list(color = col, width = 2.5),
      hovertemplate = paste0(nm, " · propio: %{y:.2f}<extra></extra>")
    )
    leyenda <- FALSE
  }
  if (mod %in% c("ONU", "Ambos") && nrow(d$fut) > 0) {
    p <- p %>% add_trace(
      type = "scatter", mode = "lines", x = d$fut$Time, y = d$fut$ONU,
      name = nm, legendgroup = e, showlegend = leyenda,
      line = list(color = col, width = 1.8, dash = "dash"),
      hovertemplate = paste0(nm, " · ONU: %{y:.2f}<extra></extra>")
    )
  }
  p
}

tema_plotly <- function(p, titulo_y = NULL, hover = "x unified") {
  p %>%
    layout(
      font = list(family = "Inter, system-ui, sans-serif", size = 13, color = "#334155"),
      paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)",
      xaxis = list(title = "", gridcolor = "#eef2f7", zeroline = FALSE),
      yaxis = list(title = titulo_y, gridcolor = "#eef2f7", zeroline = FALSE),
      hovermode = hover,
      legend = list(orientation = "h", y = -0.15),
      margin = list(l = 60, r = 20, t = 20, b = 60)
    ) %>%
    config(displaylogo = FALSE, modeBarButtonsToRemove = c("lasso2d", "select2d", "autoScale2d"))
}

linea_proyeccion <- function(p) {
  p %>% layout(
    shapes = list(list(type = "line", x0 = ANIO_HIST + 0.5, x1 = ANIO_HIST + 0.5, y0 = 0, y1 = 1,
                       yref = "paper", line = list(color = "#94a3b8", dash = "dot", width = 1))),
    annotations = list(list(x = ANIO_HIST + 1, y = 1, yref = "paper", text = "Proyección →",
                            showarrow = FALSE, xanchor = "left", font = list(size = 11, color = "#94a3b8")))
  )
}

nota <- function(...) tags$div(class = "callout-nota", ...)

css <- "
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap');
body, .content-wrapper, .main-sidebar, .main-header { font-family: 'Inter', system-ui, sans-serif; }
.content-wrapper { background: #f4f6fb; }
.card { border-radius: 14px; border: none; box-shadow: 0 2px 12px rgba(30,41,59,.07); }
.card-header { border-bottom: 1px solid #eef2f7; }
.card-title { font-weight: 600; }
.small-box { border-radius: 14px; box-shadow: 0 2px 12px rgba(30,41,59,.10); }
.small-box .inner h3 { font-weight: 700; }
.callout-nota { background: #fff7ed; border-left: 4px solid #f97316; padding: 12px 16px; border-radius: 8px; margin-bottom: 12px; }
.leyenda-lineas { font-size: 12px; color: #64748b; margin-top: 4px; }
.sidebar-var { padding: 10px 14px 0 14px; }
"

# 3. KPIs de la pantalla de inicio (estáticos) ---------------------------

kpis_inicio <- {
  cajas <- list(
    valueBox(value = n_distinct(largo$ISO3_code), subtitle = "Países analizados",
             icon = icon("globe"), color = "primary", width = 4)
  )
  if ("MedianAgePop" %in% vars_disp) {
    f <- mundo_fut %>% filter(Variable == "MedianAgePop", Time == ANIO_MAX)
    cob <- largo %>% filter(Variable == "MedianAgePop") %>% summarise(x = 100 * mean(ONU_en_IC95, na.rm = TRUE)) %>% pull(x)
    cajas <- c(cajas, list(
      valueBox(value = paste0(fmt(f$Propia, 1), " años"),
               subtitle = paste0("Edad mediana promedio en ", ANIO_MAX, " (propia) · ONU: ", fmt(f$ONU, 1)),
               icon = icon("hourglass-half"), color = "info", width = 4),
      valueBox(value = paste0(fmt(cob, 0), " %"),
               subtitle = "Proyecciones ONU de edad mediana dentro de nuestro IC95",
               icon = icon("clipboard-check"), color = "success", width = 4)
    ))
  }
  do.call(fluidRow, cajas)
}

# 4. Contenido condicional de pestañas -----------------------------------

ui_criticos <- if (TIENE_RS) {
  tagList(
    fluidRow(
      box(
        title = "Parámetros", width = 3, status = "primary",
        sliderInput("umbral", "Umbral de sostenibilidad (trabajadores activos por pensionado):",
                    min = 1.5, max = 5, value = 3, step = 0.1),
        tags$p(class = "leyenda-lineas",
               "El año crítico es el primero desde el cual la relación de soporte se mantiene por debajo del umbral hasta 2100.")
      ),
      valueBoxOutput("vb_crit_propia", width = 3),
      valueBoxOutput("vb_crit_onu",    width = 3),
      valueBoxOutput("vb_crit_dif",    width = 3)
    ),
    fluidRow(
      box(title = "Relación de soporte proyectada", width = 7, status = "primary", maximizable = TRUE,
          plotlyOutput("grafico_rs", height = "430px")),
      box(title = "Año crítico por país", width = 5, status = "primary", maximizable = TRUE,
          DTOutput("tabla_crit"),
          tags$p(class = "leyenda-lineas", "NA = no cruza el umbral de forma sostenida antes de 2100."))
    )
  )
} else {
  nota(tags$b("Esta pestaña aún no tiene datos. "),
       "El CSV no incluye la relación de soporte (RS). Deja el CSV de población por edad de la ONU en ",
       tags$code("data/raw"), ", ejecuta de nuevo el script 01 de proyecciones y recarga la app.")
}

ui_validacion <- if (!is.null(valid)) {
  tagList(
    fluidRow(
      box(title = "Error de backtesting por modelo (orígenes 1990, 2000 y 2010)", width = 7, status = "primary", maximizable = TRUE,
          plotlyOutput("grafico_valid", height = "420px"),
          tags$p(class = "leyenda-lineas",
                 "MASE < 1: el modelo supera al pronóstico ingenuo de un paso. Cada punto es un país (escala logarítmica).")),
      box(title = "Resumen (mediana entre países)", width = 5, status = "primary",
          DTOutput("tabla_valid"))
    )
  )
} else {
  nota(tags$b("Falta validacion_por_pais.csv. "), "Cópialo desde la carpeta de salida del script de modelamiento.")
}

opciones_mapa <- c("Proyección propia" = "Propia", "Proyección ONU (Medium)" = "ONU", "Discrepancia (propio − ONU)" = "Discrepancia")
if (!is.null(clusters)) opciones_mapa <- c(opciones_mapa, "Arquetipo (clúster)" = "Arquetipo")

# 5. Interfaz -------------------------------------------------------------

ui <- dashboardPage(
  title = "Trayectorias del Envejecimiento Global",
  dark = FALSE, fullscreen = TRUE, scrollToTop = TRUE, help = NULL,
  header = dashboardHeader(
    title = dashboardBrand(title = "Trayectorias 2100", color = "primary"),
    status = "white",
    rightUi = tags$li(class = "dropdown", tags$span(style = "padding:8px 14px; color:#64748b; font-size:13px;",
                                                    "DataQuest 2026"))
  ),
  sidebar = dashboardSidebar(
    skin = "light", status = "primary", elevation = 3,
    sidebarMenu(
      id = "menu",
      menuItem("Inicio",                 tabName = "inicio",        icon = icon("house")),
      menuItem("Explorador de series",   tabName = "series",        icon = icon("chart-line")),
      menuItem("Discrepancias vs ONU",   tabName = "discrepancias", icon = icon("scale-balanced")),
      menuItem("Puntos críticos",        tabName = "criticos",      icon = icon("triangle-exclamation")),
      menuItem("Mapa mundial",           tabName = "mapa",          icon = icon("earth-americas")),
      menuItem("Validación de modelos",  tabName = "validacion",    icon = icon("flask"))
    ),
    tags$div(
      class = "sidebar-var",
      tags$hr(),
      selectInput("variable", "Indicador:", choices = choices_vars, selected = vars_disp[1])
    )
  ),
  body = dashboardBody(
    tags$head(tags$style(HTML(css))),
    tabItems(
      
      # --- Inicio
      tabItem(
        tabName = "inicio",
        kpis_inicio,
        fluidRow(
          box(
            title = "¿Qué muestra este dashboard?", width = 7, status = "primary",
            tags$p("Compara las proyecciones demográficas elaboradas por nuestro equipo con la variante ",
                   tags$b("Medium"), " de la ONU (World Population Prospects 2024) hasta el año 2100,",
                   " usando solo natalidad y mortalidad, sin migración."),
            tags$ul(
              tags$li(tags$b("Explorador: "), "series observadas (1950-2023) y proyectadas, con intervalos de predicción al 95 %."),
              tags$li(tags$b("Discrepancias: "), "dónde y cuánto se separa nuestro modelo de la ONU."),
              tags$li(tags$b("Puntos críticos: "), "año en que la relación de soporte cae bajo el umbral sostenible."),
              tags$li(tags$b("Mapa: "), "la transición demográfica país por país y año por año."),
              tags$li(tags$b("Validación: "), "qué tan bien habría predicho cada modelo desde 1990, 2000 y 2010 hasta 2023.")
            )
          ),
          box(
            title = "Cómo leer los gráficos", width = 5, status = "info",
            tags$ul(
              tags$li("Línea continua gruesa antes de 2024: dato observado."),
              tags$li("Línea continua después de 2023: proyección propia; la banda es su IC95."),
              tags$li("Línea discontinua: proyección ONU (Medium)."),
              tags$li("Una diferencia con la ONU no es un “error”: son dos proyecciones con supuestos distintos.")
            ),
            tags$p(class = "leyenda-lineas",
                   "El promedio de países es un promedio simple, no ponderado por población.")
          )
        )
      ),
      
      # --- Series
      tabItem(
        tabName = "series",
        fluidRow(
          valueBoxOutput("vb_obs",  width = 3),
          valueBoxOutput("vb_prop", width = 3),
          valueBoxOutput("vb_onu",  width = 3),
          valueBoxOutput("vb_disc", width = 3)
        ),
        fluidRow(
          box(
            title = "Selección", width = 3, status = "primary",
            selectizeInput("paises_sel", "Países (hasta 8):", choices = choices_paises,
                           selected = intersect(c("COL", "CHN"), nombres$ISO3_code), multiple = TRUE,
                           options = list(maxItems = 8, placeholder = "Escribe para buscar…")),
            radioButtons("tipo_modelo", "Proyección a mostrar:",
                         choices = c("Propia y ONU" = "Ambos", "Solo propia" = "Propia", "Solo ONU" = "ONU"),
                         selected = "Ambos"),
            checkboxInput("ver_hist", "Mostrar datos observados (1950-2023)", value = !is.null(hist_l)),
            checkboxInput("ver_ic", "Mostrar intervalo de predicción 95 %", value = TRUE),
            checkboxInput("incluir_mundo", "Agregar promedio de países", value = FALSE),
            downloadButton("descarga", "Descargar datos (CSV)", class = "btn-sm btn-outline-primary"),
            tags$p(class = "leyenda-lineas", "Los indicadores de arriba corresponden al primer país seleccionado.")
          ),
          box(
            title = textOutput("titulo_series"), width = 9, status = "primary", maximizable = TRUE,
            plotlyOutput("grafico_series", height = "520px"),
            tags$p(class = "leyenda-lineas", "Continua: observado y propio · Discontinua: ONU Medium · Banda: IC95 del modelo propio.")
          )
        )
      ),
      
      # --- Discrepancias
      tabItem(
        tabName = "discrepancias",
        fluidRow(
          valueBoxOutput("vb_cobertura", width = 4),
          valueBoxOutput("vb_disc_media", width = 4),
          valueBoxOutput("vb_disc_max", width = 4)
        ),
        fluidRow(
          box(title = "Discrepancia en el tiempo (propio − ONU)", width = 7, status = "danger", maximizable = TRUE,
              plotlyOutput("grafico_disc", height = "430px"),
              tags$p(class = "leyenda-lineas", "Usa los países elegidos en el Explorador. Valores positivos: nuestro modelo proyecta más que la ONU.")),
          box(title = "Mayores discrepancias por país", width = 5, status = "danger", maximizable = TRUE,
              sliderInput("anio_rank", "Año:", min = ANIO_HIST + 1, max = ANIO_MAX, value = ANIO_MAX, step = 1, sep = ""),
              plotlyOutput("grafico_rank", height = "430px"))
        )
      ),
      
      # --- Puntos críticos
      tabItem(tabName = "criticos", ui_criticos),
      
      # --- Mapa
      tabItem(
        tabName = "mapa",
        fluidRow(
          box(
            title = "Controles del mapa", width = 3, status = "primary",
            radioButtons("fuente_mapa", "Qué mapear:", choices = opciones_mapa, selected = "Propia"),
            sliderInput("anio_mapa", "Año:", min = ANIO_HIST + 1, max = ANIO_MAX, value = ANIO_HIST + 1,
                        step = 1, sep = "", animate = animationOptions(interval = 700, loop = FALSE)),
            tags$p(class = "leyenda-lineas", "La escala de color es fija entre años para poder comparar. Pulsa ▶ para animar.")
          ),
          box(title = "Mapa mundial", width = 9, status = "primary", maximizable = TRUE,
              plotlyOutput("mapa", height = "560px"))
        )
      ),
      
      # --- Validación
      tabItem(tabName = "validacion", ui_validacion)
    ),
    footer = dashboardFooter(left = "DataQuest 2026 · Competencia Estadística",
                             right = "Fuente: UN World Population Prospects 2024")
  )
)

# 6. Servidor -------------------------------------------------------------

server <- function(input, output, session) {
  
  etiqueta_var <- reactive(unname(ETIQ[input$variable]))
  
  entidades <- reactive({
    req(input$paises_sel)
    c(input$paises_sel, if (isTRUE(input$incluir_mundo)) "MUNDO")
  })
  
  # ---- Indicadores del país foco
  foco <- reactive({
    req(input$paises_sel, input$variable)
    e <- input$paises_sel[1]; v <- input$variable
    fut <- largo %>% filter(ISO3_code == e, Variable == v, Time == ANIO_MAX)
    obs <- if (!is.null(hist_l)) {
      hist_l %>% filter(ISO3_code == e, Variable == v, Time == ANIO_HIST) %>% pull(Valor)
    } else NA_real_
    list(nom = nombre_de(e), obs = pull1(obs), prop = pull1(fut$Propia), onu = pull1(fut$ONU),
         disc = pull1(fut$Propia) - pull1(fut$ONU))
  })
  
  output$vb_obs  <- renderValueBox(valueBox(fmt(foco()$obs),  paste0(foco()$nom, " · observado ", ANIO_HIST),
                                            icon = icon("clock-rotate-left"), color = "secondary"))
  output$vb_prop <- renderValueBox(valueBox(fmt(foco()$prop), paste0(foco()$nom, " · propio ", ANIO_MAX),
                                            icon = icon("chart-line"), color = "primary"))
  output$vb_onu  <- renderValueBox(valueBox(fmt(foco()$onu),  paste0(foco()$nom, " · ONU ", ANIO_MAX),
                                            icon = icon("globe"), color = "info"))
  output$vb_disc <- renderValueBox({
    d <- foco()$disc
    valueBox(paste0(ifelse(!is.na(d) && d > 0, "+", ""), fmt(d)), paste0("Discrepancia ", ANIO_MAX, " (propio − ONU)"),
             icon = icon("scale-balanced"), color = "warning")
  })
  
  # ---- Gráfico principal
  output$titulo_series <- renderText(paste0(etiqueta_var(), ": observado y proyectado"))
  
  output$grafico_series <- renderPlotly({
    ents <- entidades(); p <- plot_ly(); idx <- 0
    for (e in ents) {
      if (e == "MUNDO") col <- COL_MUND else { idx <- idx + 1; col <- colores[(idx - 1) %% length(colores) + 1] }
      p <- trazar_entidad(p, e, input$variable, col, input$tipo_modelo, isTRUE(input$ver_hist), isTRUE(input$ver_ic))
    }
    p %>% tema_plotly(etiqueta_var()) %>% linea_proyeccion()
  })
  
  output$descarga <- downloadHandler(
    filename = function() paste0("series_", input$variable, ".csv"),
    content  = function(file) {
      write_csv(largo %>% filter(ISO3_code %in% input$paises_sel, Variable == input$variable), file)
    }
  )
  
  # ---- Discrepancias
  base_var <- reactive(largo %>% filter(Variable == input$variable))
  
  output$vb_cobertura <- renderValueBox({
    x <- 100 * mean(base_var()$ONU_en_IC95, na.rm = TRUE)
    valueBox(paste0(fmt(x, 0), " %"), "Valores ONU dentro de nuestro IC95", icon = icon("clipboard-check"), color = "success")
  })
  output$vb_disc_media <- renderValueBox({
    x <- mean(abs(base_var()$Discrepancia), na.rm = TRUE)
    valueBox(fmt(x), "Discrepancia absoluta media (todos los países y años)", icon = icon("scale-balanced"), color = "warning")
  })
  output$vb_disc_max <- renderValueBox({
    d <- base_var() %>% slice_max(abs(Discrepancia), n = 1, with_ties = FALSE)
    valueBox(fmt(d$Discrepancia), paste0("Mayor discrepancia: ", nombre_de(d$ISO3_code), " (", d$Time, ")"),
             icon = icon("triangle-exclamation"), color = "danger")
  })
  
  output$grafico_disc <- renderPlotly({
    req(input$paises_sel)
    p <- plot_ly(); idx <- 0
    for (e in input$paises_sel) {
      idx <- idx + 1; col <- colores[(idx - 1) %% length(colores) + 1]
      d <- base_var() %>% filter(ISO3_code == e) %>% arrange(Time); nm <- nombre_de(e)
      p <- p %>% add_trace(type = "scatter", mode = "lines", x = d$Time, y = d$Discrepancia, name = nm,
                           line = list(color = col, width = 2.5),
                           hovertemplate = paste0(nm, ": %{y:+.2f}<extra></extra>"))
    }
    p %>% layout(shapes = list(list(type = "line", xref = "paper", x0 = 0, x1 = 1, y0 = 0, y1 = 0,
                                    line = list(color = "#94a3b8", dash = "dot", width = 1)))) %>%
      tema_plotly("Propio − ONU")
  })
  
  output$grafico_rank <- renderPlotly({
    d <- base_var() %>% filter(Time == input$anio_rank) %>% mutate(Nombre = nombre_de(ISO3_code))
    top <- bind_rows(slice_max(d, Discrepancia, n = 8, with_ties = FALSE),
                     slice_min(d, Discrepancia, n = 8, with_ties = FALSE)) %>%
      distinct(ISO3_code, .keep_all = TRUE) %>% arrange(Discrepancia)
    plot_ly(x = top$Discrepancia, y = factor(top$Nombre, levels = top$Nombre), type = "bar", orientation = "h",
            marker = list(color = ifelse(top$Discrepancia > 0, "#dc2626", "#2563eb")),
            hovertemplate = "%{y}: %{x:+.2f}<extra></extra>") %>%
      tema_plotly(hover = "closest") %>%
      layout(margin = list(l = 130, r = 20, t = 20, b = 40), showlegend = FALSE,
             xaxis = list(title = "Propio − ONU"), yaxis = list(title = ""))
  })
  
  # ---- Puntos críticos
  if (TIENE_RS) {
    crit_tbl <- reactive({
      req(input$umbral); u <- input$umbral
      largo %>% filter(Variable == "RS") %>% arrange(ISO3_code, Time) %>%
        group_by(ISO3_code) %>%
        summarise(Critico_Propia = anio_critico(Time, Propia, u),
                  Critico_ONU    = anio_critico(Time, ONU, u), .groups = "drop") %>%
        mutate(Diferencia = Critico_Propia - Critico_ONU, Pais = nombre_de(ISO3_code))
    })
    
    foco_crit <- reactive({
      req(input$paises_sel)
      crit_tbl() %>% filter(ISO3_code == input$paises_sel[1])
    })
    txt_anio <- function(x) ifelse(is.na(x), "No cruza", as.character(x))
    
    output$vb_crit_propia <- renderValueBox(valueBox(txt_anio(foco_crit()$Critico_Propia),
                                                     paste0(nombre_de(foco_crit()$ISO3_code), " · año crítico (propio)"), icon = icon("triangle-exclamation"), color = "danger"))
    output$vb_crit_onu <- renderValueBox(valueBox(txt_anio(foco_crit()$Critico_ONU),
                                                  "Año crítico (ONU Medium)", icon = icon("globe"), color = "info"))
    output$vb_crit_dif <- renderValueBox({
      d <- foco_crit()$Diferencia
      valueBox(ifelse(is.na(d), "—", paste0(ifelse(d > 0, "+", ""), d, " años")),
               "Propio frente a la ONU (negativo = antes)", icon = icon("scale-balanced"), color = "warning")
    })
    
    output$grafico_rs <- renderPlotly({
      req(input$paises_sel, input$umbral); u <- input$umbral
      p <- plot_ly(); idx <- 0
      for (e in input$paises_sel) {
        idx <- idx + 1; col <- colores[(idx - 1) %% length(colores) + 1]
        p <- trazar_entidad(p, e, "RS", col, "Ambos", isTRUE(input$ver_hist), isTRUE(input$ver_ic))
        d <- largo %>% filter(ISO3_code == e, Variable == "RS") %>% arrange(Time)
        yc <- anio_critico(d$Time, d$Propia, u)
        if (!is.na(yc)) {
          p <- p %>% add_trace(type = "scatter", mode = "markers", x = yc, y = u, showlegend = FALSE,
                               marker = list(color = col, size = 12, symbol = "diamond", line = list(color = "white", width = 1.5)),
                               hovertemplate = paste0(nombre_de(e), " · año crítico: ", yc, "<extra></extra>"))
        }
      }
      p %>% tema_plotly("Relación de soporte (15-64 / 65+)") %>% linea_proyeccion() %>%
        layout(shapes = list(
          list(type = "line", x0 = ANIO_HIST + 0.5, x1 = ANIO_HIST + 0.5, y0 = 0, y1 = 1, yref = "paper",
               line = list(color = "#94a3b8", dash = "dot", width = 1)),
          list(type = "line", xref = "paper", x0 = 0, x1 = 1, y0 = u, y1 = u,
               line = list(color = "#dc2626", dash = "dash", width = 1.5))))
    })
    
    output$tabla_crit <- renderDT({
      d <- crit_tbl() %>% arrange(Critico_Propia) %>%
        select(Pais, ISO3_code, Critico_Propia, Critico_ONU, Diferencia)
      datatable(d, rownames = FALSE,
                colnames = c("País", "ISO3", "Año crítico (propio)", "Año crítico (ONU)", "Diferencia (años)"),
                options = list(pageLength = 8, dom = "ftip",
                               language = list(url = "//cdn.datatables.net/plug-ins/1.13.6/i18n/es-ES.json")))
    })
  }
  
  # ---- Mapa
  output$mapa <- renderPlotly({
    v <- input$variable; f <- input$fuente_mapa; yr <- input$anio_mapa
    base <- largo %>% filter(Variable == v)
    
    if (f == "Arquetipo" && !is.null(clusters)) {
      d <- base %>% filter(Time == yr) %>% inner_join(clusters, by = "ISO3_code") %>%
        mutate(z = as.numeric(factor(Cluster)), Nombre = nombre_de(ISO3_code),
               hover = paste0(Nombre, "<br>Arquetipo: ", Cluster))
      plot_geo(d) %>% add_trace(type = "choropleth", locationmode = "ISO-3", locations = d$ISO3_code,
                                z = d$z, text = d$hover, hoverinfo = "text", colorscale = "Portland",
                                showscale = FALSE, marker = list(line = list(color = "white", width = 0.4))) %>%
        layout(geo = list(showframe = FALSE, showcoastlines = FALSE, bgcolor = "rgba(0,0,0,0)",
                          projection = list(type = "natural earth")),
               paper_bgcolor = "rgba(0,0,0,0)", margin = list(l = 0, r = 0, t = 10, b = 0)) %>%
        config(displaylogo = FALSE)
    } else {
      col_val <- switch(f, Propia = "Propia", ONU = "ONU", Discrepancia = "Discrepancia", "Propia")
      rng <- range(base[[col_val]], na.rm = TRUE)
      if (col_val == "Discrepancia") { m <- max(abs(rng)); rng <- c(-m, m) }
      d <- base %>% filter(Time == yr) %>%
        mutate(z = .data[[col_val]], Nombre = nombre_de(ISO3_code),
               hover = paste0(Nombre, ": ", ifelse(col_val == "Discrepancia" & z > 0, "+", ""), round(z, 2)))
      plot_geo(d) %>% add_trace(
        type = "choropleth", locationmode = "ISO-3", locations = d$ISO3_code, z = d$z,
        text = d$hover, hoverinfo = "text",
        colorscale = if (col_val == "Discrepancia") "RdBu" else "Viridis",
        reversescale = col_val == "Discrepancia",
        zmin = rng[1], zmax = rng[2],
        marker = list(line = list(color = "white", width = 0.4)),
        colorbar = list(title = if (col_val == "Discrepancia") "Propio − ONU" else "", len = 0.7)
      ) %>%
        layout(geo = list(showframe = FALSE, showcoastlines = FALSE, bgcolor = "rgba(0,0,0,0)",
                          projection = list(type = "natural earth")),
               paper_bgcolor = "rgba(0,0,0,0)", margin = list(l = 0, r = 0, t = 10, b = 0),
               font = list(family = "Inter, system-ui, sans-serif")) %>%
        config(displaylogo = FALSE)
    }
  })
  
  # ---- Validación
  if (!is.null(valid)) {
    valid_var <- reactive({
      d <- valid %>% filter(Variable == input$variable, is.finite(MASE), MASE > 0)
      validate(need(nrow(d) > 0, "Este indicador no se validó. Prueba con otro."))
      d
    })
    
    output$grafico_valid <- renderPlotly({
      d <- valid_var()
      plot_ly(d, y = ~MASE, color = ~Modelo, type = "box", boxpoints = "outliers",
              hovertemplate = "MASE: %{y:.2f}<extra></extra>") %>%
        tema_plotly("MASE (escala log)", hover = "closest") %>%
        layout(yaxis = list(type = "log", title = "MASE (escala log)"), showlegend = TRUE,
               shapes = list(list(type = "line", xref = "paper", x0 = 0, x1 = 1, y0 = 1, y1 = 1,
                                  line = list(color = "#dc2626", dash = "dash", width = 1.2))))
    })
    
    output$tabla_valid <- renderDT({
      d <- valid_var() %>% group_by(Modelo) %>%
        summarise(MAE = median(MAE, na.rm = TRUE), RMSE = median(RMSE, na.rm = TRUE),
                  MASE = median(MASE, na.rm = TRUE), Paises = n(), .groups = "drop") %>%
        arrange(MASE) %>% mutate(across(c(MAE, RMSE, MASE), ~ round(.x, 3)))
      datatable(d, rownames = FALSE, options = list(dom = "t", pageLength = 10))
    })
  }
}

# 7. Ejecutar -------------------------------------------------------------
shinyApp(ui, server)