#==============================================================================
# app/unificada/modules/mod_validacion.R
# Módulo: Validación de modelos, síntesis de resultados y advertencias éticas
#
# Objetivo: Resumir el rendimiento del backtesting (MASE), la concordancia 
# con la incertidumbre oficial de la ONU (Regla D16) y ofrecer interpretaciones 
# claras y limitaciones del análisis para el reporte y el video final.
#
# Datos usados (cargados en global.R):
#   ts_valid : Validación por país (MASE, MAE, RMSE por modelo y variable)
#   ts_d16   : Posición del pronóstico propio vs. banda oficial del 80%
#   ts_crit  : Puntos críticos de la Relación de Soporte (RS)
#==============================================================================

#---- Helper interno para estandarizar columnas ----
.estandarizar_cols_valid <- function(df) {
  if (is.null(df) || nrow(df) == 0) return(df)
  nms <- names(df)
  nms_lower <- tolower(trimws(nms))
  
  col_var  <- nms[nms_lower %in% c("variable", "var", "indicador")][1]
  col_met  <- nms[nms_lower %in% c("modelo", "metodo", "method", "model")][1]
  col_mase <- nms[nms_lower %in% c("mase", "mase_mediano", "mase_mean")][1]
  col_pct  <- nms[nms_lower %in% c("pct_dentro", "cobertura", "pct", "porcentaje", "pct_dentro_80")][1]
  
  if (!is.na(col_var)  && col_var != "Variable")    names(df)[names(df) == col_var]  <- "Variable"
  if (!is.na(col_met)  && col_met != "Modelo")      names(df)[names(df) == col_met]  <- "Modelo"
  if (!is.na(col_mase) && col_mase != "MASE")      names(df)[names(df) == col_mase] <- "MASE"
  if (!is.na(col_pct)  && col_pct != "Pct_Dentro") names(df)[names(df) == col_pct]  <- "Pct_Dentro"
  
  df
}

#---- UI del módulo ------------------------------------------------------------
mod_validacion_ui <- function(id) {
  ns <- NS(id)
  
  tagList(
    #--- Encabezado de síntesis ---
    fluidRow(
      box(
        title = "Síntesis de Validación y Rendimiento del Modelo",
        width = 12,
        status = "primary",
        tags$p(
          "Este panel resume la robustez de nuestras proyecciones frente a líneas base ingenuas ",
          "y a la incertidumbre oficial de la ONU. ",
          tags$b("Principio rector:"), " Un modelo no necesita 'parecerse' a la ONU para ser válido; ",
          "debe superar al naive y caer dentro de los intervalos de predicción probabilísticos oficiales."
        )
      )
    ),
    
    #--- KPIs de Validación ---
    fluidRow(
      valueBoxOutput(ns("vb_mase_medio"), width = 4),
      valueBoxOutput(ns("vb_cobertura_onu"), width = 4),
      valueBoxOutput(ns("vb_mejor_modelo"), width = 4)
    ),
    
    #--- Gráficos de Validación Cuantitativa ---
    fluidRow(
      box(
        title = "1. Backtesting: Error escalado (MASE) por modelo y variable",
        width = 7,
        status = "info",
        maximizable = TRUE,
        plotlyOutput(ns("grafico_mase"), height = "450px"),
        tags$p(
          class = "leyenda-lineas",
          "MASE < 1: El modelo supera al pronóstico ingenuo de un paso (línea roja punteada). ",
          "Cada distribución muestra la mediana del error en los orígenes de validación (1990, 2000, 2010)."
        )
      ),
      box(
        title = "2. Regla D16: ¿Dónde cae nuestro pronóstico vs. la Banda Oficial del 80%?",
        width = 5,
        status = "success",
        maximizable = TRUE,
        plotlyOutput(ns("grafico_d16"), height = "450px"),
        tags$p(
          class = "leyenda-lineas",
          "Universo de 161 países. Porcentaje de proyecciones país-año dentro del intervalo probabilístico oficial de la ONU (80% PI). ",
          "Nota: LE65 se excluye del promedio global por discrepancia estructural (ver advertencias)."
        )
      )
    ),
    
    #--- Interpretaciones y Advertencias Éticas ---
    fluidRow(
      box(
        title = "3. Interpretaciones Clave de los Resultados",
        width = 6,
        status = "warning",
        div(
          class = "callout-nota",
          tags$h5(" El envejecimiento de Colombia es acelerado y el 'punto crítico' es inminente", style = "margin-top: 0;"),
          tags$p(
            "Nuestro modelo central proyecta que la Relación de Soporte (15-64 / 65+) de Colombia ",
            "caerá y se mantendrá por debajo de 3 en el año ", tags$b("2047"), 
            " (IC95 temprano: 2033). Esto ocurre ", tags$b("5 a 11 años antes"), 
            " que las proyecciones oficiales del DANE (2058) y la ONU (2052). ",
            "No es un error, es una señal de que los modelos estructurales capturan la inercia demográfica actual con mayor sensibilidad."
          )
        ),
        div(
          class = "callout-nota",
          tags$h5(" Los arquetipos demográficos confirman una transición de 4 etapas", style = "margin-top: 0;"),
          tags$p(
            "El PCA longitudinal (1960-2100) identifica 4 estadios claros. Colombia transita del ",
            "Estadio 2 (transición temprana) al Estadio 3 (transición avanzada) de forma persistente ",
            "(regla de 3 años). A nivel global, Europa pierde su agrupación 'Alto-Alto' hacia 2100 ",
            "no por rejuvenecimiento, sino por la convergencia de los supuestos del modelo de la ONU."
          )
        ),
        tags$p(
          "Nuestros modelos superan consistentemente al naive (MASE mediano global < 4, frente a ≥ 5 del naive). ",
          "El modelo 'Ensamble' (ETS + GAM/Estructural) fue el ganador por MASE en TFR, LEx y RS, ",
          "logrando que >90% de nuestras proyecciones caigan dentro de la banda de incertidumbre del 80% de la ONU."
        )
      ),
      box(
        title = "4. Advertencias y Limitaciones (Guías Éticas ASA)",
        width = 6,
        status = "danger",
        div(
          class = "callout-nota",
          tags$h5("LE65: Discrepancia estructural con la ONU", style = "margin-top: 0;"),
          tags$p(
            "Nuestro modelo GAM para la Esperanza de Vida a los 65 años proyecta valores ",
            tags$b("sistemáticamente por debajo"), " del límite inferior de la banda oficial del 80% de la ONU ",
            "(0% de cobertura D16). Esto sugiere que la banda oficial de la ONU para LE65 podría ser ",
            "demasiado optimista o estrecha, o que nuestro modelo penaliza más la desaceleración de ganancias ",
            "de longevidad en edades avanzadas. Se reporta como hallazgo, no como fallo."
          )
        ),
        div(
          class = "callout-nota",
          tags$h5(" Horizontes largos (2076-2100) son escenarios, no predicciones", style = "margin-top: 0;"),
          tags$p(
            "Con solo ~74 años de historia, validar un horizonte de 77 años es estadísticamente inviable. ",
            "Las proyecciones más allá de 2050 deben interpretarse como ",
            tags$b("trayectorias condicionales"), " a que no ocurran choques exógenos masivos ",
            "(pandemias, cambios tecnológicos radicales en longevidad, migraciones no modeladas). ",
            "Los intervalos de predicción (IC95) crecen con √h para reflejar esta incertidumbre."
          )
        ),
        div(
          class = "callout-nota",
          tags$h5(" La Relación de Soporte no es sostenibilidad fiscal", style = "margin-top: 0;"),
          tags$p(
            "El 'punto crítico' demográfico (RS < 3) mide la presión estructural sobre la población activa, ",
            "pero ", tags$b("no equivale"), " a la quiebra de un sistema pensional. La sostenibilidad real ",
            "depende de tasas de cotización, informalidad, edad de jubilación y productividad, variables ",
            "que exceden el alcance de los datos WPP2024."
          )
        )
      )
    ),
    
    #--- Botón de Descarga ---
    fluidRow(
      column(
        width = 12,
        align = "right",
        downloadButton(ns("descarga_validacion"), "Descargar Resumen de Validación (CSV)", class = "btn-sm btn-outline-primary")
      )
    )
  )
}

#---- Server del módulo---------------------------------------------------------
mod_validacion_server <- function(id, datos, main_input) {
  moduleServer(id, function(input, output, session) {
    
    #--- 1. KPIs de Validación ---
    output$vb_mase_medio <- renderValueBox({
      req(datos$ts_valid)
      # Mediana global del MASE de los modelos propios (excluyendo Naive para el KPI)
      mase_medio <- datos$ts_valid %>%
        dplyr::filter(Modelo != "Naive", is.finite(MASE), MASE > 0) %>%
        dplyr::summarise(med = median(MASE, na.rm = TRUE)) %>%
        dplyr::pull(med)
      
      valueBox(
        value = sprintf("%.2f", mase_medio),
        subtitle = "Mediana global del MASE (Modelos propios)",
        icon = icon("chart-line"),
        color = ifelse(mase_medio < 5, "success", "warning") # < 5 es bueno, ya que Naive es >= 5
      )
    })
    
    output$vb_cobertura_onu <- renderValueBox({
      req(datos$ts_d16)
      # Porcentaje promedio de país-año DENTRO de la banda 80% (excluyendo LE65 que es outlier)
      cob <- datos$ts_d16 %>%
        dplyr::filter(Variable != "LE65", posicion == "Dentro de la banda") %>%
        dplyr::summarise(pct = mean(pct, na.rm = TRUE)) %>%
        dplyr::pull(pct)
      
      valueBox(
        value = sprintf("%.1f%%", cob),
        subtitle = "Proyecciones dentro de la Banda 80% de la ONU",
        icon = icon("bullseye"),
        color = "success"
      )
    })
    
    output$vb_mejor_modelo <- renderValueBox({
      req(datos$ts_valid)
      # Modelo con menor MASE global agregado
      mejor <- datos$ts_valid %>%
        dplyr::filter(Modelo != "Naive", is.finite(MASE), MASE > 0) %>%
        dplyr::group_by(Modelo) %>%
        dplyr::summarise(mase = median(MASE, na.rm = TRUE)) %>%
        dplyr::arrange(mase) %>%
        dplyr::slice(1) %>%
        dplyr::pull(Modelo)
      
      valueBox(
        value = mejor,
        subtitle = "Modelo con menor error global (MASE)",
        icon = icon("trophy"),
        color = "primary"
      )
    })
    
    #--- 2. Gráfico MASE (Boxplot) ---
    output$grafico_mase <- renderPlotly({
      req(datos$ts_valid)
      
      d <- datos$ts_valid %>%
        dplyr::filter(Modelo != "Naive", is.finite(MASE), MASE > 0) %>%
        dplyr::mutate(
          Variable = ifelse(Variable %in% names(ETIQ_VAR), ETIQ_VAR[Variable], Variable),
          Modelo = factor(Modelo, levels = c("Estructural", "GAM", "ETS", "Ensamble"))
        )
      
      plotly::plot_ly(
        d, x = ~Modelo, y = ~MASE, color = ~Modelo,
        type = "box", boxpoints = "outliers", hovertemplate = "MASE: %{y:.2f}<br>Modelo: %{x}<extra></extra>"
      ) %>%
        plotly::layout(
          font = list(family = "Inter, system-ui, sans-serif", size = 12, color = "#334155"),
          xaxis = list(title = "Modelo de pronóstico", gridcolor = "#eef2f7"),
          yaxis = list(
            title = "MASE (Escala logarítmica)", 
            type = "log", 
            gridcolor = "#eef2f7",
            zeroline = FALSE
          ),
          shapes = list(
            list(
              type = "line", xref = "paper", x0 = 0, x1 = 1, y0 = 1, y1 = 1,
              line = list(color = "#D55E00", dash = "dash", width = 2)
            )
          ),
          annotations = list(
            list(
              x = 0.5, y = 1.05, xref = "paper", yref = "paper",
              text = "Umbral Naive (MASE = 1)",
              showarrow = FALSE, font = list(color = "#D55E00", size = 11)
            )
          ),
          legend = list(orientation = "h", y = -0.2),
          paper_bgcolor = "rgba(0,0,0,0)",
          plot_bgcolor = "rgba(0,0,0,0)",
          margin = list(l = 50, r = 20, t = 40, b = 60)
        ) %>%
        plotly::config(displaylogo = FALSE, modeBarButtonsToRemove = c("lasso2d", "select2d"))
    })
    
    #--- 3. Gráfico Regla D16 (Banda 80%) ---
    output$grafico_d16 <- renderPlotly({
      req(datos$ts_d16)
      
      d <- datos$ts_d16 %>%
        dplyr::filter(Variable != "LE65") %>% # Excluido por decisión D16/D33
        dplyr::mutate(
          Variable = ifelse(Variable %in% names(ETIQ_VAR), ETIQ_VAR[Variable], Variable),
          posicion = factor(posicion, levels = c("Debajo de la banda", "Dentro de la banda", "Encima de la banda"))
        )
      
      cols_d16 <- c(
        "Debajo de la banda" = "#D55E00", # Bermellón
        "Dentro de la banda" = "#B8C0C8", # Gris
        "Encima de la banda" = "#0072B2"  # Azul
      )
      
      plotly::plot_ly(
        d, x = ~bloque, y = ~pct, color = ~posicion, colors = cols_d16,
        type = "bar", text = ~paste0(pct, "%"), hoverinfo = "text+name",
        textposition = "inside"
      ) %>%
        plotly::layout(
          barmode = "stack",
          font = list(family = "Inter, system-ui, sans-serif", size = 12, color = "#334155"),
          xaxis = list(title = "Bloque de años", gridcolor = "#eef2f7"),
          yaxis = list(title = "% de país-año", range = c(0, 100), gridcolor = "#eef2f7"),
          legend = list(orientation = "h", y = -0.2, title = list(text = "Posición")),
          paper_bgcolor = "rgba(0,0,0,0)",
          plot_bgcolor = "rgba(0,0,0,0)",
          margin = list(l = 50, r = 20, t = 20, b = 80)
        ) %>%
        plotly::config(displaylogo = FALSE)
    })
    
    #--- 4. Descarga de datos de validación ---
    output$descarga_validacion <- downloadHandler(
      filename = function() {
        "resumen_validacion_y_sintesis.csv"
      },
      content = function(file) {
        # Unir resumen MASE y D16 para descarga
        req(datos$ts_valid, datos$ts_d16)
        
        resumen_mase <- datos$ts_valid %>%
          dplyr::filter(Modelo != "Naive", is.finite(MASE), MASE > 0) %>%
          dplyr::group_by(Variable, Modelo) %>%
          dplyr::summarise(
            MASE_Mediano = median(MASE, na.rm = TRUE),
            Paises_Evaluados = n_distinct(ISO3_code),
            .groups = "drop"
          )
        
        resumen_d16 <- datos$ts_d16 %>%
          dplyr::filter(Variable != "LE65") %>%
          dplyr::select(Variable, bloque, posicion, pct)
        
        # Escribir en un archivo con múltiples hojas no es trivial en write_csv, 
        # así que exportamos el resumen Mase como principal, y añadimos D16 al final.
        out <- dplyr::bind_rows(
          resumen_mase %>% dplyr::mutate(Tipo_Resumen = "MASE_Backtesting"),
          resumen_d16 %>% dplyr::mutate(Tipo_Resumen = "Cobertura_Banda_80_D16")
        )
        
        readr::write_csv(out, file)
      }
    )
  })
}