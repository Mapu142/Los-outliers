#==============================================================================
# mod_criticos.R · Puntos críticos de la relación de soporte (RS = 15-64 / 65+)
# Año crítico = primer año desde el cual la RS SE MANTIENE bajo el umbral hasta
# el final de la ventana. Triangulación para Colombia: propio, ONU y DANE.
# NOTA: es un indicador demográfico; NO mide sostenibilidad pensional (plan §9).
#==============================================================================

anio_critico <- function(t, rs, umbral) {
  ok <- rs < umbral
  if (length(ok) == 0 || all(is.na(ok))) return(NA_real_)
  if (all(ok, na.rm = TRUE)) return(min(t))          # ya está bajo el umbral
  if (!isTRUE(tail(ok, 1))) return(NA_real_)         # no se estabiliza antes del final
  max(t[!ok], na.rm = TRUE) + 1
}

mod_criticos_ui <- function(id) {
  ns <- NS(id)
  if (!"RS" %in% VARS_DISP) {
    return(box(title = "Puntos críticos", width = 12, status = "warning",
               tags$p("Los CSV de series de tiempo no incluyen la relación de soporte (RS). ",
                      "Copia poblacion_por_edad.csv a data/raw/ y re-ejecuta el script 10.")))
  }
  tagList(
    fluidRow(
      box(title = "Parámetros", width = 3, status = "primary",
          sliderInput(ns("umbral"), "Umbral (personas 15-64 por persona de 65+):",
                      min = 1.5, max = 5, value = 3, step = 0.1),
          checkboxInput(ns("solo_univ"), "Solo universo D12 (161 países ≥ 1 millón)", TRUE),
          tags$p(class = "leyenda-lineas",
                 "Umbrales = escenarios, no estándares. Los países seleccionados en el panel lateral se grafican abajo.")),
      valueBoxOutput(ns("vb_prop"), width = 3),
      valueBoxOutput(ns("vb_onu"),  width = 3),
      valueBoxOutput(ns("vb_dif"),  width = 3)
    ),
    fluidRow(
      box(title = "Relación de soporte: observada, propia (IC95), ONU y DANE", width = 7,
          status = "primary", maximizable = TRUE,
          plotlyOutput(ns("g_rs"), height = "430px"),
          tags$p(class = "leyenda-lineas",
                 "Línea continua: propio · discontinua: ONU Medium · punteada verde: DANE (solo Colombia, 2018-2070) · ◆ año crítico propio.")),
      box(title = "Año crítico por país", width = 5, status = "primary", maximizable = TRUE,
          DTOutput(ns("tabla")),
          tags$p(class = "leyenda-lineas",
                 "NA = no cruza de forma sostenida antes de 2100. 2024 = ya estaba bajo el umbral. ",
                 "IC95: banda propia (temprano = RS baja antes)."))
    ),
    fluidRow(
      box(title = "Triangulación para Colombia", width = 12, status = "info", maximizable = TRUE,
          fluidRow(column(7, plotlyOutput(ns("g_triang"), height = "300px")),
                   column(5, DTOutput(ns("t_triang")))),
          tags$p(class = "leyenda-lineas",
                 "La ONU y el DANE son dos proyecciones oficiales con modelos y supuestos distintos (DANE: versión de julio 2025, horizonte 2070). ",
                 "La diferencia no indica cuál es más acertada."))
    )
  )
}

mod_criticos_server <- function(id, datos, main_input) {
  moduleServer(id, function(input, output, session) {
    if (!"RS" %in% VARS_DISP) return(invisible(NULL))
    
    nombre <- function(iso) {
      n <- datos$nombres$Location[match(iso, datos$nombres$ISO3_code)]
      ifelse(is.na(n), iso, n)
    }
    alpha_col <- function(hex, a = 0.15) {
      r <- grDevices::col2rgb(hex); sprintf("rgba(%d,%d,%d,%.2f)", r[1], r[2], r[3], a)
    }
    txt <- function(x) ifelse(is.na(x), "No cruza", ifelse(x <= 2024, "≤ 2024", as.character(x)))
    
    rs      <- datos$ts_largo %>% dplyr::filter(Variable == "RS") %>% dplyr::arrange(ISO3_code, Time)
    hist_rs <- datos$ts_hist  %>% dplyr::filter(Variable == "RS") %>% dplyr::arrange(ISO3_code, Time)
    universo <- unique(datos$pca_coord$ISO3_code)       # los 161 países del PCA (D12)
    
    # ---- Tabla de años críticos (depende del umbral) ----
    crit <- reactive({
      req(input$umbral); u <- input$umbral
      d <- if (isTRUE(input$solo_univ)) dplyr::filter(rs, ISO3_code %in% universo) else rs
      d %>% dplyr::group_by(ISO3_code) %>%
        dplyr::summarise(C_prop = anio_critico(Time, Propia, u),
                         C_onu  = anio_critico(Time, ONU, u),
                         C_temp = anio_critico(Time, lo95, u),
                         C_tard = anio_critico(Time, hi95, u), .groups = "drop") %>%
        dplyr::mutate(Dif = C_prop - C_onu, Pais = nombre(ISO3_code))
    })
    foco <- reactive({
      req(main_input$g_paises)
      rs_all <- dplyr::filter(rs, ISO3_code == main_input$g_paises[1])
      u <- input$umbral
      list(iso = main_input$g_paises[1],
           prop = anio_critico(rs_all$Time, rs_all$Propia, u),
           onu  = anio_critico(rs_all$Time, rs_all$ONU, u))
    })
    
    output$vb_prop <- renderValueBox(valueBox(txt(foco()$prop),
                                              paste0(nombre(foco()$iso), " · año crítico (propio)"),
                                              icon = icon("triangle-exclamation"), color = "danger"))
    output$vb_onu <- renderValueBox(valueBox(txt(foco()$onu),
                                             "Año crítico (ONU Medium)", icon = icon("globe"), color = "info"))
    output$vb_dif <- renderValueBox({
      d <- foco()$prop - foco()$onu
      valueBox(ifelse(is.na(d), "—", paste0(ifelse(d > 0, "+", ""), d, " años")),
               "Propio − ONU (negativo = el propio cruza antes)",
               icon = icon("scale-balanced"), color = "warning")
    })
    
    # ---- Gráfico de RS ----
    output$g_rs <- renderPlotly({
      paises <- main_input$g_paises; req(paises, input$umbral)
      u <- input$umbral; a <- main_input$g_anios
      p <- plotly::plot_ly()
      for (i in seq_along(paises)) {
        iso <- paises[i]; col <- COL_SERIES[(i - 1) %% length(COL_SERIES) + 1]; nm <- nombre(iso)
        h  <- hist_rs %>% dplyr::filter(ISO3_code == iso, Time >= a[1], Time <= a[2])
        pr <- rs %>% dplyr::filter(ISO3_code == iso)
        pw <- dplyr::filter(pr, Time >= a[1], Time <= a[2])
        if (nrow(h) > 0)
          p <- p %>% plotly::add_trace(type = "scatter", mode = "lines", x = h$Time, y = h$Valor,
                                       name = nm, legendgroup = iso, line = list(color = col, width = 3),
                                       hovertemplate = paste0(nm, " · observado: %{y:.2f}<extra></extra>"))
        if (nrow(pw) > 0) {
          p <- p %>%
            plotly::add_trace(type = "scatter", mode = "lines",
                              x = c(pw$Time, rev(pw$Time)), y = c(pw$hi95, rev(pw$lo95)),
                              fill = "toself", fillcolor = alpha_col(col), line = list(width = 0),
                              legendgroup = iso, showlegend = FALSE, hoverinfo = "skip") %>%
            plotly::add_trace(type = "scatter", mode = "lines", x = pw$Time, y = pw$Propia,
                              name = nm, legendgroup = iso, showlegend = (nrow(h) == 0),
                              line = list(color = col, width = 3),
                              hovertemplate = paste0(nm, " · propio: %{y:.2f}<extra></extra>")) %>%
            plotly::add_trace(type = "scatter", mode = "lines", x = pw$Time, y = pw$ONU,
                              name = nm, legendgroup = iso, showlegend = FALSE,
                              line = list(color = col, width = 1.8, dash = "dash"),
                              hovertemplate = paste0(nm, " · ONU: %{y:.2f}<extra></extra>"))
        }
        yc <- anio_critico(pr$Time, pr$Propia, u)
        if (!is.na(yc))
          p <- p %>% plotly::add_trace(type = "scatter", mode = "markers", x = yc, y = u,
                                       showlegend = FALSE, legendgroup = iso,
                                       marker = list(color = col, size = 12, symbol = "diamond",
                                                     line = list(color = "white", width = 1.5)),
                                       hovertemplate = paste0(nm, " · año crítico: ", yc, "<extra></extra>"))
      }
      if ("COL" %in% paises && !is.null(datos$dane_ind)) {
        dn <- datos$dane_ind %>% dplyr::filter(anio >= 2018, anio >= a[1], anio <= a[2])
        p <- p %>% plotly::add_trace(type = "scatter", mode = "lines", x = dn$anio, y = dn$psr65,
                                     name = "Colombia · DANE", line = list(color = "#009E73", width = 2.2, dash = "dot"),
                                     hovertemplate = "Colombia · DANE: %{y:.2f}<extra></extra>")
      }
      p %>% plotly::layout(
        font = list(family = "Inter, system-ui, sans-serif", size = 13, color = "#334155"),
        xaxis = list(title = "", gridcolor = "#eef2f7", zeroline = FALSE),
        yaxis = list(title = "RS (15-64 / 65+)", gridcolor = "#eef2f7", zeroline = FALSE, rangemode = "tozero"),
        hovermode = "x unified", legend = list(orientation = "h", y = -0.15),
        paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)",
        shapes = list(
          list(type = "line", xref = "paper", x0 = 0, x1 = 1, y0 = u, y1 = u,
               line = list(color = "#D55E00", dash = "dash", width = 1.5)),
          list(type = "line", x0 = ANIO_CORTE + 0.5, x1 = ANIO_CORTE + 0.5, y0 = 0, y1 = 1,
               yref = "paper", line = list(color = "#94a3b8", dash = "dot", width = 1)))) %>%
        plotly::config(displaylogo = FALSE)
    })
    
    # ---- Tabla por país ----
    output$tabla <- renderDT({
      d <- crit() %>% dplyr::arrange(C_prop) %>%
        dplyr::select(Pais, ISO3_code, C_prop, C_temp, C_tard, C_onu, Dif)
      DT::datatable(d, rownames = FALSE, filter = "top",
                    colnames = c("País", "ISO3", "Propio", "IC95 temprano", "IC95 tardío", "ONU", "Dif. (años)"),
                    options = list(pageLength = 8, dom = "ftip", scrollX = TRUE)) %>%
        DT::formatStyle("Dif", color = DT::styleInterval(0, c("#D55E00", "#0072B2")),
                        fontWeight = "bold")
    })
    
    # ---- Triangulación Colombia (reglas comparables: sostenido hasta fin de ventana) ----
    triang <- reactive({
      req(input$umbral); u <- input$umbral
      r <- dplyr::filter(rs, ISO3_code == "COL"); req(nrow(r) > 0)
      f <- function(src, y, regla) tibble::tibble(Fuente = src, Anio = y, Ventana = regla)
      r70 <- dplyr::filter(r, Time <= 2070)
      out <- dplyr::bind_rows(
        f("Propio · IC95 temprano", anio_critico(r$Time, r$lo95, u),  "hasta 2100"),
        f("Propio · central",       anio_critico(r$Time, r$Propia, u), "hasta 2100"),
        f("Propio · IC95 tardío",   anio_critico(r$Time, r$hi95, u),  "hasta 2100"),
        f("ONU Medium",             anio_critico(r$Time, r$ONU, u),   "hasta 2100"),
        f("ONU Medium (ventana DANE)", anio_critico(r70$Time, r70$ONU, u), "hasta 2070"),
        if (!is.null(datos$dane_ind)) {
          dn <- dplyr::filter(datos$dane_ind, anio >= 2024)
          f("DANE (jul. 2025)", anio_critico(dn$anio, dn$psr65, u), "hasta 2070")
        })
      out
    })
    output$t_triang <- renderDT({
      d <- triang() %>% dplyr::mutate(Anio = txt(Anio))
      DT::datatable(d, rownames = FALSE, options = list(dom = "t", pageLength = 10))
    })
    output$g_triang <- renderPlotly({
      d <- triang() %>% dplyr::filter(!is.na(Anio)) %>%
        dplyr::mutate(Fuente = factor(Fuente, levels = rev(unique(Fuente))))
      validate(need(nrow(d) > 0, "Ninguna fuente cruza el umbral elegido."))
      plotly::plot_ly(d, x = ~Anio, y = ~Fuente, type = "scatter", mode = "markers",
                      marker = list(size = 13, color = "#D55E00"),
                      text = ~paste0(Fuente, ": ", Anio, " (", Ventana, ")"), hoverinfo = "text") %>%
        plotly::layout(xaxis = list(title = "Año en que la RS baja del umbral", gridcolor = "#eef2f7"),
                       yaxis = list(title = ""),
                       paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)",
                       margin = list(l = 190),
                       font = list(family = "Inter, system-ui, sans-serif", size = 13)) %>%
        plotly::config(displaylogo = FALSE)
    })
  })
}