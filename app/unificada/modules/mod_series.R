#==============================================================================
# modules/mod_series.R
# Módulo: Explorador de series históricas y proyectadas
#==============================================================================

# Función auxiliar interna para estandarizar nombres de columnas de forma robusta
.estandarizar_cols_series <- function(df) {
  if (is.null(df) || nrow(df) == 0) return(df)
  
  nms <- names(df)
  nms_lower <- tolower(trimws(nms))
  
  # Buscar coincidencias por patrón
  idx_iso  <- which(nms_lower %in% c("iso3_code", "iso3", "iso", "codigo", "country_code"))[1]
  idx_loc  <- which(nms_lower %in% c("location", "pais", "nombre", "nom_pais", "location_name"))[1]
  idx_var  <- which(nms_lower %in% c("variable", "var", "indicador", "metric"))[1]
  idx_time <- which(nms_lower %in% c("time", "anio", "year", "fecha"))[1]
  idx_val  <- which(nms_lower %in% c("valor", "val", "value", "resultado", "pob", "y", "pred", "estimacion"))[1]
  idx_lo   <- which(nms_lower %in% c("lo95", "lo_95", "ic_lo", "lower", "q2.5"))[1]
  idx_hi   <- which(nms_lower %in% c("hi95", "hi_95", "ic_hi", "upper", "q97.5"))[1]
  
  # Renombrar columnas encontradas
  if (!is.na(idx_iso))  names(df)[idx_iso]  <- "ISO3_code"
  if (!is.na(idx_loc))  names(df)[idx_loc]  <- "Location"
  if (!is.na(idx_var))  names(df)[idx_var]  <- "Variable"
  if (!is.na(idx_time)) names(df)[idx_time] <- "Time"
  if (!is.na(idx_val))  names(df)[idx_val]  <- "Valor"
  if (!is.na(idx_lo))   names(df)[idx_lo]   <- "lo95"
  if (!is.na(idx_hi))   names(df)[idx_hi]   <- "hi95"
  
  # Si aún no existe 'Valor', buscar la primera columna numérica que no sea Time ni identificador
  if (!"Valor" %in% names(df)) {
    cols_num <- sapply(df, is.numeric)
    cols_cand <- setdiff(names(df)[cols_num], c("Time", "year", "anio", "LocID", "lo95", "hi95"))
    if (length(cols_cand) > 0) {
      names(df)[names(df) == cols_cand[1]] <- "Valor"
    }
  }
  
  # Garantizar etiquetas de ubicación si faltaran
  if (!"Location" %in% names(df) && "ISO3_code" %in% names(df)) df$Location <- df$ISO3_code
  if (!"ISO3_code" %in% names(df) && "Location" %in% names(df)) df$ISO3_code <- df$Location
  
  df
}

#---- UI del módulo ------------------------------------------------------------
mod_series_ui <- function(id) {
  ns <- NS(id)
  
  fluidRow(
    column(
      width = 12,
      box(
        title = tags$div(
          icon("chart-line"),
          " Explorador de series: histórico vs. proyección"
        ),
        width = 12,
        status = "primary",
        solidHeader = TRUE,
        collapsible = TRUE,
        
        fluidRow(
          column(
            width = 4,
            selectInput(
              inputId = ns("tipo_linea"),
              label = "Tipo de visualización",
              choices = c(
                "Histórico + Proyección" = "ambos",
                "Solo Histórico" = "historico",
                "Solo Proyección" = "proyeccion"
              ),
              selected = "ambos"
            )
          ),
          column(
            width = 4,
            checkboxInput(
              inputId = ns("mostrar_ic"),
              label = "Mostrar IC 95%",
              value = TRUE
            )
          ),
          column(
            width = 4,
            checkboxInput(
              inputId = ns("mostrar_mundo"),
              label = "Mostrar promedio mundial",
              value = FALSE
            )
          )
        ),
        
        plotlyOutput(
          outputId = ns("grafico_series"),
          height = "500px"
        ),
        
        tags$p(
          class = "leyenda-lineas",
          tags$span(style = "color:#0072B2; font-weight:bold;", "■"),
          " Azul = estimación (≤ 2023) · ",
          tags$span(style = "color:#E69F00; font-weight:bold;", "■"),
          " Naranja = proyección propia · ",
          tags$span(style = "color:#D55E00; font-weight:bold;", "■"),
          " Bermellón = ONU Medium · ",
          tags$span(style = "color:#999999;", "░"),
          " Banda = IC 95% empírico"
        )
      )
    )
  )
}

#---- Server del módulo --------------------------------------------------------
mod_series_server <- function(id, datos, main_input) {
  moduleServer(id, function(input, output, session) {
    
    # Estandarizar y filtrar datos reactivamente
    datos_filtrados <- reactive({
      req(main_input$g_paises, main_input$g_variable, main_input$g_anios)
      req(datos$ts_hist, datos$ts_largo)
      
      paises_sel <- main_input$g_paises
      var_sel    <- main_input$g_variable
      anios_sel  <- main_input$g_anios
      
      hist_std <- .estandarizar_cols_series(datos$ts_hist)
      proy_std <- .estandarizar_cols_series(datos$ts_largo)
      
      # Filtrar histórico
      hist_filtrado <- hist_std |>
        dplyr::filter(
          ISO3_code %in% paises_sel,
          Variable == var_sel,
          Time >= anios_sel[1],
          Time <= anios_sel[2]
        )
      
      # Filtrar proyecciones
      proy_filtrado <- proy_std |>
        dplyr::filter(
          ISO3_code %in% paises_sel,
          Variable == var_sel,
          Time >= anios_sel[1],
          Time <= anios_sel[2]
        )
      
      list(hist = hist_filtrado, proy = proy_filtrado, hist_full = hist_std, proy_full = proy_std)
    })
    
    # Renderizar gráfico Plotly
    output$grafico_series <- renderPlotly({
      df_list <- datos_filtrados()
      
      # Validaciones previas para evitar colapsos de Plotly
      validate(
        need(!is.null(df_list), "Cargando datos..."),
        need(nrow(df_list$hist) > 0 || nrow(df_list$proy) > 0, 
             "No hay datos disponibles para los países e indicador seleccionados.")
      )
      
      hist <- df_list$hist
      proy <- df_list$proy
      var_actual <- main_input$g_variable
      paises_actual <- main_input$g_paises
      anios_actual <- main_input$g_anios
      
      # Seleccionar según la opción elegida por el usuario
      if (input$tipo_linea == "historico") {
        df_plot <- hist
        if (nrow(df_plot) > 0) df_plot$Tipo <- "Histórico"
      } else if (input$tipo_linea == "proyeccion") {
        df_plot <- proy
        if (nrow(df_plot) > 0) df_plot$Tipo <- "Proyección"
      } else {
        if (nrow(hist) > 0) hist$Tipo <- "Histórico"
        if (nrow(proy) > 0) proy$Tipo <- "Proyección"
        df_plot <- dplyr::bind_rows(hist, proy)
      }
      
      validate(
        need(nrow(df_plot) > 0, "No hay filas para graficar en el rango seleccionado."),
        need("Valor" %in% names(df_plot), "La columna de datos 'Valor' no está presente en la tabla.")
      )
      
      # Generar gráfico interactivo
      p <- plot_ly(
        data = df_plot,
        x = ~Time,
        y = ~Valor,
        color = ~Tipo,
        colors = c("Histórico" = "#0072B2", "Proyección" = "#E69F00"),
        type = "scatter",
        mode = "lines",
        line = list(width = 3),
        hoverinfo = "x+y+text",
        text = ~paste0(
          "<b>", Location, "</b><br>",
          "Año: ", Time, "<br>",
          "Valor: ", scales::comma(Valor, accuracy = 0.01), "<br>",
          "Tipo: ", Tipo
        )
      )
      
      # Añadir IC 95% si aplica
      if (input$mostrar_ic && input$tipo_linea != "historico" && "lo95" %in% names(df_list$proy_full)) {
        proy_ic <- df_list$proy_full |>
          dplyr::filter(
            ISO3_code %in% paises_actual,
            Variable == var_actual,
            Time >= anios_actual[1],
            Time <= anios_actual[2],
            !is.na(lo95),
            !is.na(hi95)
          )
        
        if (nrow(proy_ic) > 0) {
          p <- p |>
            add_ribbons(
              data = proy_ic,
              x = ~Time,
              ymin = ~lo95,
              ymax = ~hi95,
              line = list(color = "transparent"),
              fillcolor = "rgba(100, 100, 100, 0.15)",
              name = "IC 95%",
              showlegend = TRUE,
              hoverinfo = "skip"
            )
        }
      }
      
      # Añadir línea de referencia mundial si aplica
      if (input$mostrar_mundo) {
        mundo_hist <- df_list$hist_full |>
          dplyr::filter(
            Variable == var_actual,
            ISO3_code %in% c("WLD", "WORLD") | Location %in% c("World", "Mundo"),
            Time >= anios_actual[1],
            Time <= anios_actual[2]
          )
        
        mundo_proy <- df_list$proy_full |>
          dplyr::filter(
            Variable == var_actual,
            ISO3_code %in% c("WLD", "WORLD") | Location %in% c("World", "Mundo"),
            Time >= anios_actual[1],
            Time <= anios_actual[2]
          )
        
        if (nrow(mundo_hist) > 0 || nrow(mundo_proy) > 0) {
          mundo_comb <- dplyr::bind_rows(mundo_hist, mundo_proy)
          mundo_comb$Tipo <- "Mundo"
          
          p <- p |>
            add_lines(
              data = mundo_comb,
              x = ~Time,
              y = ~Valor,
              line = list(color = "#000000", width = 2, dash = "dot"),
              name = "Mundo",
              showlegend = TRUE
            )
        }
      }
      
      # Configuración estética
      etiq_nombre <- if (!is.null(datos$ETIQ_VAR) && !is.na(datos$ETIQ_VAR[var_actual])) {
        datos$ETIQ_VAR[var_actual]
      } else {
        var_actual
      }
      
      p <- p |>
        layout(
          title = list(
            text = paste0(
              "<b>", etiq_nombre, "</b><br>",
              "<sup>", paste(paises_actual, collapse = ", "), "</sup>"
            ),
            x = 0.5,
            font = list(size = 14)
          ),
          xaxis = list(
            title = "Año",
            showgrid = TRUE,
            gridcolor = "#e0e0e0"
          ),
          yaxis = list(
            title = etiq_nombre,
            showgrid = TRUE,
            gridcolor = "#e0e0e0"
          ),
          hovermode = "x unified",
          showlegend = TRUE,
          legend = list(
            x = 0.02,
            y = 0.98,
            xanchor = "left",
            yanchor = "top"
          ),
          margin = list(l = 80, r = 20, t = 80, b = 60)
        )
      
      p
    })
    
    # Manejador de descarga de datos
    output$download_datos <- downloadHandler(
      filename = function() {
        paste0("series_", main_input$g_variable, "_", Sys.Date(), ".csv")
      },
      content = function(file) {
        datos_combo <- datos_filtrados()
        write.csv(
          dplyr::bind_rows(datos_combo$hist, datos_combo$proy),
          file,
          row.names = FALSE
        )
      }
    )
  })
}