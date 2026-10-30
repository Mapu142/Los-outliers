#==============================================================================
# mod_discrepancias.R · Discrepancias: pronóstico propio vs ONU Medium
# Usa filtros globales: g_paises, g_variable, g_anios
# Datos: ts_largo (Propia, ONU, Discrepancia, ONU_en_IC95), ts_d16 (resumen D16)
#==============================================================================

mod_disc_ui <- function(id) {
  ns <- NS(id)
  tagList(
    fluidRow(
      valueBoxOutput(ns("vb_cob"),   width = 4),
      valueBoxOutput(ns("vb_media"), width = 4),
      valueBoxOutput(ns("vb_max"),   width = 4)
    ),
    fluidRow(
      box(title = "Discrepancia en el tiempo (propio − ONU)", width = 7,
          status = "danger", maximizable = TRUE,
          plotlyOutput(ns("g_tiempo"), height = "400px"),
          tags$p(class = "leyenda-lineas",
                 "Países elegidos en el panel lateral. Positivo: el modelo propio proyecta más que la ONU. ",
                 "No es un error: son dos proyecciones con supuestos distintos.")),
      box(title = "Mayores discrepancias por país", width = 5,
          status = "danger", maximizable = TRUE,
          sliderInput(ns("anio_rank"), "Año:", min = 2024, max = ANIO_MAX,
                      value = ANIO_MAX, step = 1, sep = ""),
          plotlyOutput(ns("g_rank"), height = "340px"))
    ),
    fluidRow(
      box(title = "¿Cae el pronóstico propio fuera de la banda oficial del 80 %? (regla D16)",
          width = 12, status = "primary", maximizable = TRUE,
          plotlyOutput(ns("g_d16"), height = "320px"),
          tags$p(class = "leyenda-lineas",
                 "Universo de 161 países. Banda = [mín, máx] de Lower/Upper 80 PI (D14). ",
                 "Solo disponible para indicadores con intervalos oficiales (no LE60, IRG, RS; LE65 excluido por inconsistencia)."))
    )
  )
}

mod_disc_server <- function(id, datos, main_input) {
  moduleServer(id, function(input, output, session) {
    
    nombre <- function(iso) {
      n <- datos$nombres$Location[match(iso, datos$nombres$ISO3_code)]
      ifelse(is.na(n), iso, n)
    }
    fmt <- function(x, d = 2) ifelse(is.na(x), "—", formatC(x, format = "f", digits = d))
    
    # Variable y años globales
    base_var <- reactive({
      req(main_input$g_variable, main_input$g_anios)
      a <- main_input$g_anios
      datos$ts_largo %>%
        dplyr::filter(Variable == main_input$g_variable, Time >= a[1], Time <= a[2])
    })
    
    # ---- Value boxes ----
    output$vb_cob <- renderValueBox({
      d <- base_var(); req(nrow(d) > 0)
      valueBox(paste0(fmt(100 * mean(d$ONU_en_IC95, na.rm = TRUE), 0), " %"),
               "Valores ONU dentro del IC95 propio (mide el ancho de mi intervalo)",
               icon = icon("clipboard-check"), color = "success")
    })
    output$vb_media <- renderValueBox({
      d <- base_var(); req(nrow(d) > 0)
      valueBox(fmt(mean(abs(d$Discrepancia), na.rm = TRUE)),
               "Discrepancia absoluta media (países y años del filtro)",
               icon = icon("scale-balanced"), color = "warning")
    })
    output$vb_max <- renderValueBox({
      d <- base_var(); req(nrow(d) > 0)
      m <- d %>% dplyr::slice_max(abs(Discrepancia), n = 1, with_ties = FALSE)
      valueBox(fmt(m$Discrepancia),
               paste0("Mayor discrepancia: ", nombre(m$ISO3_code), " (", m$Time, ")"),
               icon = icon("triangle-exclamation"), color = "danger")
    })
    
    # ---- Serie de discrepancia ----
    output$g_tiempo <- renderPlotly({
      d <- base_var(); paises <- main_input$g_paises
      validate(need(nrow(d) > 0, "Sin datos de proyección en el rango de años elegido (la proyección empieza en 2024)."),
               need(length(paises) > 0, "Selecciona al menos un país."))
      p <- plotly::plot_ly()
      for (i in seq_along(paises)) {
        iso <- paises[i]; col <- COL_SERIES[(i - 1) %% length(COL_SERIES) + 1]
        s <- d %>% dplyr::filter(ISO3_code == iso) %>% dplyr::arrange(Time)
        if (nrow(s) == 0) next
        p <- p %>% plotly::add_trace(
          type = "scatter", mode = "lines", x = s$Time, y = s$Discrepancia,
          name = nombre(iso), line = list(color = col, width = 2.8),
          hovertemplate = paste0(nombre(iso), ": %{y:+.2f}<extra></extra>"))
      }
      p %>% plotly::layout(
        font = list(family = "Inter, system-ui, sans-serif", size = 13, color = "#334155"),
        xaxis = list(title = "", gridcolor = "#eef2f7", zeroline = FALSE),
        yaxis = list(title = "Propio − ONU", gridcolor = "#eef2f7", zeroline = TRUE,
                     zerolinecolor = "#94a3b8"),
        hovermode = "x unified", legend = list(orientation = "h", y = -0.15),
        paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)") %>%
        plotly::config(displaylogo = FALSE)
    })
    
    # ---- Ranking por año (todos los países) ----
    output$g_rank <- renderPlotly({
      req(main_input$g_variable, input$anio_rank)
      d <- datos$ts_largo %>%
        dplyr::filter(Variable == main_input$g_variable, Time == input$anio_rank) %>%
        dplyr::mutate(Nombre = nombre(ISO3_code))
      validate(need(nrow(d) > 0, "Sin datos para ese año."))
      top <- dplyr::bind_rows(dplyr::slice_max(d, Discrepancia, n = 8, with_ties = FALSE),
                              dplyr::slice_min(d, Discrepancia, n = 8, with_ties = FALSE)) %>%
        dplyr::distinct(ISO3_code, .keep_all = TRUE) %>% dplyr::arrange(Discrepancia)
      plotly::plot_ly(x = top$Discrepancia, y = factor(top$Nombre, levels = top$Nombre),
                      type = "bar", orientation = "h",
                      marker = list(color = ifelse(top$Discrepancia > 0, "#D55E00", "#0072B2")),
                      hovertemplate = "%{y}: %{x:+.2f}<extra></extra>") %>%
        plotly::layout(margin = list(l = 130, r = 10, t = 10, b = 40),
                       xaxis = list(title = "Propio − ONU", gridcolor = "#eef2f7"),
                       yaxis = list(title = ""),
                       paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)",
                       font = list(family = "Inter, system-ui, sans-serif", size = 12)) %>%
        plotly::config(displaylogo = FALSE)
    })
    
    # ---- Regla D16: posición frente a la banda oficial del 80 % ----
    output$g_d16 <- renderPlotly({
      validate(need(!is.null(datos$ts_d16), "Falta 11_d16_posicion_vs_banda80.csv (ejecuta el script 11)."))
      v <- main_input$g_variable
      d <- datos$ts_d16 %>% dplyr::filter(Variable == v, Variable != "LE65")
      validate(need(nrow(d) > 0,
                    paste0("«", v, "» no tiene banda oficial 80 % comparable. Elige MedianAgePop, TFR, LEx o CBR.")))
      niv <- c("Debajo de la banda", "Dentro de la banda", "Encima de la banda")
      cols <- c("Debajo de la banda" = "#D55E00", "Dentro de la banda" = "#B8C0C8",
                "Encima de la banda" = "#0072B2")
      d <- d %>% dplyr::mutate(posicion = factor(posicion, levels = niv))
      plotly::plot_ly(d, x = ~bloque, y = ~pct, color = ~posicion, colors = cols,
                      type = "bar", text = ~paste0(pct, " %"), hoverinfo = "text+name") %>%
        plotly::layout(barmode = "stack",
                       xaxis = list(title = "Bloque de años"),
                       yaxis = list(title = "% de país-año", range = c(0, 100)),
                       legend = list(orientation = "h", y = -0.2),
                       paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)",
                       font = list(family = "Inter, system-ui, sans-serif", size = 13)) %>%
        plotly::config(displaylogo = FALSE)
    })
  })
}