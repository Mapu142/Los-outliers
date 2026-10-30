#==============================================================================
# app/unificada/modules/mod_series.R
# Módulo: Explorador de series históricas y proyectadas
#
# Usa los filtros globales del sidebar (g_paises, g_variable, g_anios) que
# llegan en `main_input`, y sus propios controles (tipo_linea, mostrar_ic,
# mostrar_mundo).
#
# Columnas esperadas:
#   ts_hist  : ISO3_code, Location, Variable, Time, Valor
#   ts_largo : ISO3_code, Variable, Time, Propia, ONU, lo95, hi95
#==============================================================================

con_alpha <- function(hex, a = 0.15) {
  r <- grDevices::col2rgb(hex)
  sprintf("rgba(%d,%d,%d,%.2f)", r[1], r[2], r[3], a)
}

#---- UI del módulo -------------------------------------------------------------
mod_series_ui <- function(id) {
  ns <- NS(id)
  fluidRow(
    box(
      title = "Opciones", width = 3, status = "primary",
      radioButtons(ns("tipo_linea"), "Mostrar:",
                   choices = c("Histórico y proyección" = "ambos",
                               "Solo histórico"         = "historico",
                               "Solo proyección"        = "proyeccion"),
                   selected = "ambos"),
      checkboxInput(ns("mostrar_ic"),    "Mostrar IC 95 % (modelo propio)", TRUE),
      checkboxInput(ns("mostrar_onu"),   "Mostrar proyección ONU (discontinua)", TRUE),
      checkboxInput(ns("mostrar_mundo"), "Agregar promedio de países", FALSE),
      tags$p(class = "leyenda-lineas",
             "Los países, el indicador y el rango de años se eligen en el panel lateral.")
    ),
    box(
      title = textOutput(ns("titulo")), width = 9, status = "primary",
      maximizable = TRUE,
      plotlyOutput(ns("grafico_series"), height = "520px"),
      tags$p(class = "leyenda-lineas",
             "Continua: observado y propio · Discontinua: ONU Medium · Banda: IC95 del modelo propio.")
    )
  )
}

#---- Server del módulo ---------------------------------------------------------
mod_series_server <- function(id, datos, main_input) {
  moduleServer(id, function(input, output, session) {
    
    output$titulo <- renderText({
      v <- main_input$g_variable
      etiq <- if (!is.null(v) && v %in% names(ETIQ_VAR)) ETIQ_VAR[[v]] else v
      paste0(etiq, ": observado y proyectado")
    })
    
    # Datos filtrados por los controles globales
    datos_sel <- reactive({
      req(main_input$g_paises, main_input$g_variable, main_input$g_anios)
      p <- main_input$g_paises
      v <- main_input$g_variable
      a <- main_input$g_anios
      
      hist <- datos$ts_hist %>%
        dplyr::filter(ISO3_code %in% p, Variable == v, Time >= a[1], Time <= a[2]) %>%
        dplyr::arrange(ISO3_code, Time)
      
      proy <- datos$ts_largo %>%
        dplyr::filter(ISO3_code %in% p, Variable == v, Time >= a[1], Time <= a[2]) %>%
        dplyr::arrange(ISO3_code, Time)
      
      list(hist = hist, proy = proy)
    })
    
    output$grafico_series <- renderPlotly({
      d   <- datos_sel()
      v   <- main_input$g_variable
      a   <- main_input$g_anios
      tipo <- input$tipo_linea
      
      validate(need(nrow(d$hist) > 0 || nrow(d$proy) > 0,
                    "No hay datos para los países, indicador y años seleccionados."))
      
      ver_hist <- tipo %in% c("ambos", "historico")
      ver_proy <- tipo %in% c("ambos", "proyeccion")
      
      paises <- main_input$g_paises
      nombre <- function(iso) {
        n <- datos$nombres$Location[match(iso, datos$nombres$ISO3_code)]
        ifelse(is.na(n), iso, n)
      }
      
      p <- plotly::plot_ly()
      
      for (i in seq_along(paises)) {
        iso <- paises[i]
        col <- COL_SERIES[(i - 1) %% length(COL_SERIES) + 1]
        nm  <- nombre(iso)
        h   <- d$hist %>% dplyr::filter(ISO3_code == iso)
        pr  <- d$proy %>% dplyr::filter(ISO3_code == iso)
        primera <- TRUE
        
        if (ver_hist && nrow(h) > 0) {
          p <- p %>% plotly::add_trace(
            type = "scatter", mode = "lines", x = h$Time, y = h$Valor,
            name = nm, legendgroup = iso, showlegend = primera,
            line = list(color = col, width = 3),
            hovertemplate = paste0(nm, " · observado: %{y:.2f}<extra></extra>"))
          primera <- FALSE
        }
        
        if (ver_proy && nrow(pr) > 0) {
          if (isTRUE(input$mostrar_ic) && all(c("lo95", "hi95") %in% names(pr))) {
            ic <- pr %>% dplyr::filter(!is.na(lo95), !is.na(hi95))
            if (nrow(ic) > 0) {
              p <- p %>% plotly::add_trace(
                type = "scatter", mode = "lines",
                x = c(ic$Time, rev(ic$Time)), y = c(ic$hi95, rev(ic$lo95)),
                fill = "toself", fillcolor = con_alpha(col, 0.15),
                line = list(width = 0), legendgroup = iso,
                showlegend = FALSE, hoverinfo = "skip")
            }
          }
          p <- p %>% plotly::add_trace(
            type = "scatter", mode = "lines", x = pr$Time, y = pr$Propia,
            name = nm, legendgroup = iso, showlegend = primera,
            line = list(color = col, width = 3),
            hovertemplate = paste0(nm, " · propio: %{y:.2f}<extra></extra>"))
          primera <- FALSE
          
          if (isTRUE(input$mostrar_onu)) {
            p <- p %>% plotly::add_trace(
              type = "scatter", mode = "lines", x = pr$Time, y = pr$ONU,
              name = nm, legendgroup = iso, showlegend = FALSE,
              line = list(color = col, width = 1.8, dash = "dash"),
              hovertemplate = paste0(nm, " · ONU: %{y:.2f}<extra></extra>"))
          }
        }
      }
      
      # Promedio simple de todos los países
      if (isTRUE(input$mostrar_mundo)) {
        col_m <- "#475569"
        if (ver_hist) {
          mh <- datos$ts_hist %>%
            dplyr::filter(Variable == v, Time >= a[1], Time <= a[2]) %>%
            dplyr::group_by(Time) %>%
            dplyr::summarise(Valor = mean(Valor, na.rm = TRUE), .groups = "drop")
          if (nrow(mh) > 0) {
            p <- p %>% plotly::add_trace(
              type = "scatter", mode = "lines", x = mh$Time, y = mh$Valor,
              name = "Promedio de países", legendgroup = "mundo",
              line = list(color = col_m, width = 2),
              hovertemplate = "Promedio · observado: %{y:.2f}<extra></extra>")
          }
        }
        if (ver_proy) {
          mp <- datos$ts_largo %>%
            dplyr::filter(Variable == v, Time >= a[1], Time <= a[2]) %>%
            dplyr::group_by(Time) %>%
            dplyr::summarise(Propia = mean(Propia, na.rm = TRUE), .groups = "drop")
          if (nrow(mp) > 0) {
            p <- p %>% plotly::add_trace(
              type = "scatter", mode = "lines", x = mp$Time, y = mp$Propia,
              name = "Promedio de países", legendgroup = "mundo",
              showlegend = !ver_hist,
              line = list(color = col_m, width = 2, dash = "dot"),
              hovertemplate = "Promedio · propio: %{y:.2f}<extra></extra>")
          }
        }
      }
      
      etiq <- if (v %in% names(ETIQ_VAR)) ETIQ_VAR[[v]] else v
      p %>% plotly::layout(
        font = list(family = "Inter, system-ui, sans-serif", size = 13, color = "#334155"),
        xaxis = list(title = "", gridcolor = "#eef2f7", zeroline = FALSE),
        yaxis = list(title = etiq, gridcolor = "#eef2f7", zeroline = FALSE),
        hovermode = "x unified",
        paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)",
        legend = list(orientation = "h", y = -0.15),
        shapes = list(list(type = "line", x0 = ANIO_CORTE + 0.5, x1 = ANIO_CORTE + 0.5,
                           y0 = 0, y1 = 1, yref = "paper",
                           line = list(color = "#94a3b8", dash = "dot", width = 1)))
      ) %>%
        plotly::config(displaylogo = FALSE)
    })
  })
}

