# ==============================================================================
# R/mod_pca_clusters.R
# Módulo Shiny: PCA longitudinal y estadios demográficos · DataQuest 2026
#
# Uso dentro de la app del equipo:
#   ui      ->  mod_pca_ui("pca")            (varianza, trayectorias, estadios)
#               mod_transiciones_ui("pca")   (transiciones; mismo id)
#   server  ->  mod_pca_server("pca", datos = cargar_datos_pca())
#
# El módulo NO recalcula nada: lee los archivos que genera R/02_pca_y_clustering.R
#   data/clean : wpp_pca_coordenadas_todo_periodo.parquet
#                wpp_matriz_arquetipos_proyecciones.parquet
#   tablas     : 02_pca_autovalores.csv, 02_pca_calidad_variables.csv,
#                02_cluster_centroides.csv
# Las transiciones se calculan aquí con la misma regla de persistencia del
# script, pero con la racha mínima elegida por la persona usuaria.
# ==============================================================================

library(shiny)
library(dplyr)
library(tidyr)
library(ggplot2)
library(ggrepel)
library(DT)
library(arrow)

# ---- Constantes ---------------------------------------------------------------
PER_HIST <- "Histórico (hasta 2023)"
PER_PROY <- "Proyección (2024-2100)"

EJES_PC <- c("PC1 · Madurez"    = "PC1_Madurez",
             "PC2 · Dinámica"   = "PC2_Dinamica",
             "PC3 · Estructura" = "PC3_Estructura")

# Nombres propuestos tras revisar las cargas (ajustar si cambia el modelo)
NOMBRES_PC <- c(PC1_Madurez    = "Madurez demográfica estructural",
                PC2_Dinamica   = "Velocidad del envejecimiento",
                PC3_Estructura = "Balance natural (reemplazo)")
IDX_PC   <- c(PC1_Madurez = 1, PC2_Dinamica = 2, PC3_Estructura = 3)
COL_LOAD <- c(PC1_Madurez = "PC1_load", PC2_Dinamica = "PC2_load", PC3_Estructura = "PC3_load")

# ---- Utilidades visuales (usan R/tema.R si está cargado) ----------------------
# Texto de ayuda: une los fragmentos con espacios para evitar palabras pegadas
ayuda <- function(...) helpText(paste(...))

col_acento <- function() {
  if (exists("PAL") && !is.null(PAL$acento)) PAL$acento else "#1F6F8B"
}

tema_app <- function() {
  if (exists("theme_dataquest")) theme_dataquest(rejilla = "xy") else theme_minimal(base_size = 12)
}

# Paleta secuencial de joven a envejecido; funciona con cualquier número de estadios
paleta_arq <- function(niveles) {
  setNames(
    grDevices::colorRampPalette(c("#2A9D8F", "#E9C46A", "#E76F51", "#8B1E3F"))(length(niveles)),
    niveles
  )
}

etiqueta_eje <- function(eje, eig) {
  sprintf("%s: %s (%.1f %%)", sub("_.*", "", eje), NOMBRES_PC[[eje]],
          eig$variance.percent[IDX_PC[[eje]]])
}

# ---- Carga de datos -----------------------------------------------------------
cargar_datos_pca <- function(dir_clean = CFG$dir_clean, dir_tablas = CFG$dir_tablas) {
  f <- list(
    coord = file.path(dir_clean,  "wpp_pca_coordenadas_todo_periodo.parquet"),
    arq   = file.path(dir_clean,  "wpp_matriz_arquetipos_proyecciones.parquet"),
    eig   = file.path(dir_tablas, "02_pca_autovalores.csv"),
    vars  = file.path(dir_tablas, "02_pca_calidad_variables.csv"),
    cent  = file.path(dir_tablas, "02_cluster_centroides.csv")
  )
  faltan <- names(f)[!file.exists(unlist(f))]
  if (length(faltan) > 0) {
    stop("Faltan archivos de la Fase 2: ",
         paste(basename(unlist(f[faltan])), collapse = ", "),
         ". Ejecute primero R/02_pca_y_clustering.R.", call. = FALSE)
  }
  
  cent <- read.csv(f$cent, check.names = FALSE)
  names(cent)[1] <- "Arquetipo"          # la primera columna son los nombres de fila
  niveles <- cent$Arquetipo              # ya vienen ordenados de joven a envejecido
  
  coord <- as.data.frame(arrow::read_parquet(f$coord))
  arq   <- as.data.frame(arrow::read_parquet(f$arq))
  arq$Cluster_Arquetipo <- factor(as.character(arq$Cluster_Arquetipo), levels = niveles)
  
  list(coord = coord, arq = arq,
       eig = read.csv(f$eig), vars = read.csv(f$vars), cent = cent)
}

# ---- Transiciones persistentes (misma regla que el script de la Fase 2) -------
# Una transición se cuenta solo si el país permanece al menos `racha` años en el
# nuevo estadio. Devuelve una fila por transición, con estadio de origen y destino.
transiciones_persistentes <- function(df, racha = 3) {
  df %>%
    arrange(ISO3_code, Time) %>%
    group_by(ISO3_code) %>%
    mutate(run = consecutive_id(Cluster_Arquetipo)) %>%
    group_by(ISO3_code, run) %>%
    mutate(largo = n(), inicio = Time == min(Time)) %>%
    ungroup() %>%
    filter(inicio, largo >= racha) %>%
    group_by(ISO3_code) %>%
    mutate(Desde = lag(Cluster_Arquetipo)) %>%
    ungroup() %>%
    filter(!is.na(Desde), Desde != Cluster_Arquetipo) %>%
    transmute(ISO3_code, Location, Continente, Anio = Time,
              Desde, Hacia = Cluster_Arquetipo)
}

# ---- UI -----------------------------------------------------------------------
mod_pca_ui <- function(id) {
  ns <- NS(id)
  
  tabsetPanel(
    id = ns("tabs"),
    
    # 1. Varianza y cargas ------------------------------------------------------
    tabPanel(
      "Varianza y cargas",
      sidebarLayout(
        sidebarPanel(
          width = 3,
          h4("Círculo de correlación"),
          selectInput(ns("circ_x"), "Eje horizontal", EJES_PC, selected = "PC1_Madurez"),
          selectInput(ns("circ_y"), "Eje vertical",   EJES_PC, selected = "PC2_Dinamica"),
          hr(),
          ayuda("Variables del mismo lado del eje se mueven juntas; las de lados",
                "opuestos se mueven en sentido contrario. Cuanto más cerca del",
                "círculo, mejor representada está la variable en ese plano.")
        ),
        mainPanel(
          width = 9,
          fluidRow(
            column(6, plotOutput(ns("scree"),   height = 380)),
            column(6, plotOutput(ns("circulo"), height = 380))
          ),
          h4("Cargas, calidad de representación (cos2) y contribución (%)"),
          DTOutput(ns("tabla_cargas"))
        )
      )
    ),
    
    # 2. Trayectorias -----------------------------------------------------------
    tabPanel(
      "Trayectorias",
      sidebarLayout(
        sidebarPanel(
          width = 3,
          selectizeInput(ns("paises"), "Países (máximo 8)", choices = NULL,
                         multiple = TRUE, options = list(maxItems = 8)),
          selectInput(ns("tray_x"), "Eje horizontal", EJES_PC, selected = "PC1_Madurez"),
          selectInput(ns("tray_y"), "Eje vertical",   EJES_PC, selected = "PC2_Dinamica"),
          sliderInput(ns("anios"), "Años", min = 1960, max = 2100,
                      value = c(1960, 2100), step = 1, sep = ""),
          checkboxInput(ns("ver_fondo"), "Mostrar todos los países (cada 5 años)", TRUE),
          checkboxInput(ns("ver_centroides"), "Mostrar centroides de los estadios", FALSE),
          ayuda("Línea continua: histórico. Línea discontinua: proyección.",
                "Las etiquetas marcan cada 20 años.")
        ),
        mainPanel(width = 9, plotOutput(ns("plano"), height = 580))
      )
    ),
    
    # 3. Estadios ---------------------------------------------------------------
    tabPanel(
      "Estadios",
      sidebarLayout(
        sidebarPanel(
          width = 3,
          selectInput(ns("continente"), "Continente", choices = "Todos"),
          sliderInput(ns("anio_sel"), "Año", min = 2024, max = 2100,
                      value = 2024, step = 1, sep = "", animate = TRUE),
          ayuda("Cada estadio agrupa país-años con un perfil demográfico similar.",
                "El estadio 1 es el más joven y el último, el más envejecido.")
        ),
        mainPanel(
          width = 9,
          plotOutput(ns("area"), height = 340),
          h4(textOutput(ns("titulo_tabla"))),
          DTOutput(ns("tabla_estadios")),
          h4("Centroides en el espacio de componentes"),
          DTOutput(ns("tabla_centroides"))
        )
      )
    )
  )
}

# UI de la pestaña de transiciones. Va aparte para poder ubicarla en su propio
# menú (la app unificada tiene "Arquetipos (PCA)" y "Transiciones" separados).
# Debe usar el mismo id que mod_pca_ui() y mod_pca_server().
mod_transiciones_ui <- function(id) {
  ns <- NS(id)
  
  sidebarLayout(
    sidebarPanel(
      width = 3,
      sliderInput(ns("racha"), "Años mínimos en el nuevo estadio",
                  min = 1, max = 8, value = 3, step = 1),
      selectInput(ns("continente_t"), "Continente", choices = "Todos"),
      ayuda("Una transición solo se cuenta si el país permanece al menos ese",
            "número de años en el nuevo estadio. Con 1 año se cuentan todos",
            "los cambios, incluidos los que se revierten."),
      hr(),
      h5("Colombia"),
      uiOutput(ns("col_texto"))
    ),
    mainPanel(
      width = 9,
      plotOutput(ns("hist_trans"), height = 320),
      DTOutput(ns("tabla_trans"))
    )
  )
}

# ---- Server -------------------------------------------------------------------
mod_pca_server <- function(id, datos) {
  moduleServer(id, function(input, output, session) {
    
    niveles <- levels(datos$arq$Cluster_Arquetipo)
    pal     <- paleta_arq(niveles)
    acento  <- col_acento()
    
    # Selectores que dependen de los datos
    paises <- datos$coord %>% distinct(ISO3_code, Location) %>% arrange(Location)
    updateSelectizeInput(session, "paises",
                         choices  = setNames(paises$ISO3_code, paises$Location),
                         selected = intersect("COL", paises$ISO3_code),
                         server   = TRUE)
    
    conts <- c("Todos", sort(unique(na.omit(datos$arq$Continente))))
    updateSelectInput(session, "continente",   choices = conts)
    updateSelectInput(session, "continente_t", choices = conts)
    
    racha0 <- if (exists("CFG") && !is.null(CFG$racha_cruce)) CFG$racha_cruce else 3
    updateSliderInput(session, "racha", value = racha0)
    
    # ---- 1. Varianza y cargas --------------------------------------------------
    output$scree <- renderPlot({
      e <- datos$eig
      e$Dimension <- factor(e$Dimension, levels = e$Dimension)
      ggplot(e, aes(Dimension, variance.percent)) +
        geom_col(fill = acento, width = 0.7) +
        geom_line(aes(y = cumulative.variance.percent, group = 1), linewidth = 0.7) +
        geom_point(aes(y = cumulative.variance.percent), size = 2) +
        geom_text(aes(label = sprintf("%.1f%%", variance.percent)), vjust = -0.5, size = 3.4) +
        scale_y_continuous(limits = c(0, 105)) +
        labs(title = "Varianza explicada por componente",
             subtitle = "Barras: por componente. Línea: acumulada.",
             x = NULL, y = "% de la varianza") +
        tema_app()
    })
    
    output$circulo <- renderPlot({
      ex <- input$circ_x
      ey <- input$circ_y
      validate(need(ex != ey, "Elige dos ejes distintos."))
      lx <- COL_LOAD[[ex]]
      ly <- COL_LOAD[[ey]]
      th <- seq(0, 2 * pi, length.out = 200)
      
      ggplot(datos$vars, aes(x = .data[[lx]], y = .data[[ly]])) +
        annotate("path", x = cos(th), y = sin(th), colour = "grey60",
                 linewidth = 0.3, linetype = "dashed") +
        geom_vline(xintercept = 0, colour = "grey70", linewidth = 0.2) +
        geom_hline(yintercept = 0, colour = "grey70", linewidth = 0.2) +
        geom_segment(aes(x = 0, y = 0, xend = .data[[lx]], yend = .data[[ly]]),
                     arrow = arrow(length = unit(0.2, "cm")),
                     colour = acento, linewidth = 0.8) +
        geom_text_repel(aes(label = Variable), fontface = "bold", size = 3.6) +
        coord_fixed(xlim = c(-1.05, 1.05), ylim = c(-1.05, 1.05)) +
        labs(title = "Círculo de correlación",
             x = etiqueta_eje(ex, datos$eig),
             y = etiqueta_eje(ey, datos$eig)) +
        tema_app()
    })
    
    output$tabla_cargas <- renderDT({
      v <- datos$vars
      datatable(v, rownames = FALSE,
                options = list(dom = "t", pageLength = 10, scrollX = TRUE)) %>%
        formatRound(columns = setdiff(names(v), "Variable"), digits = 3)
    })
    
    # ---- 2. Trayectorias -------------------------------------------------------
    output$plano <- renderPlot({
      ex <- input$tray_x
      ey <- input$tray_y
      validate(
        need(ex != ey, "Elige dos ejes distintos."),
        need(length(input$paises) > 0, "Selecciona al menos un país.")
      )
      a <- input$anios
      
      tray <- datos$coord %>%
        filter(ISO3_code %in% input$paises, Time >= a[1], Time <= a[2]) %>%
        mutate(periodo = if_else(Time >= 2024, PER_PROY, PER_HIST))
      # Duplicar 2023 en la proyección para que la línea no quede cortada
      puente <- tray %>% filter(Time == 2023) %>% mutate(periodo = PER_PROY)
      tray   <- bind_rows(tray, puente) %>% arrange(ISO3_code, periodo, Time)
      
      hitos <- tray %>%
        filter(Time %% 20 == 0) %>%
        distinct(ISO3_code, Time, .keep_all = TRUE)
      
      p <- ggplot()
      if (isTRUE(input$ver_fondo)) {
        fondo <- datos$coord %>% filter(Time >= a[1], Time <= a[2], Time %% 5 == 0)
        p <- p + geom_point(data = fondo, aes(.data[[ex]], .data[[ey]]),
                            colour = "grey80", size = 0.6, alpha = 0.5)
      }
      if (isTRUE(input$ver_centroides)) {
        p <- p +
          geom_point(data = datos$cent, aes(.data[[ex]], .data[[ey]]),
                     shape = 18, size = 5, colour = "black") +
          geom_text_repel(data = datos$cent,
                          aes(.data[[ex]], .data[[ey]], label = Arquetipo),
                          fontface = "bold", size = 3.4, colour = "black")
      }
      p +
        geom_path(data = tray,
                  aes(.data[[ex]], .data[[ey]], colour = Location, linetype = periodo,
                      group = interaction(ISO3_code, periodo)),
                  linewidth = 0.9) +
        geom_point(data = hitos,
                   aes(.data[[ex]], .data[[ey]], colour = Location), size = 2) +
        geom_text_repel(data = hitos,
                        aes(.data[[ex]], .data[[ey]], label = Time, colour = Location),
                        size = 3, show.legend = FALSE, max.overlaps = Inf) +
        scale_linetype_manual(values = setNames(c("solid", "dashed"), c(PER_HIST, PER_PROY)),
                              name = NULL) +
        scale_colour_brewer(palette = "Dark2", name = NULL) +
        labs(title = "Trayectorias en el plano de componentes",
             subtitle = "Cada punto es un país en un año. Las líneas siguen al país en el tiempo.",
             x = etiqueta_eje(ex, datos$eig),
             y = etiqueta_eje(ey, datos$eig)) +
        tema_app() +
        theme(legend.position = "bottom")
    })
    
    # ---- 3. Estadios -----------------------------------------------------------
    arq_filtrado <- reactive({
      d <- datos$arq
      if (!is.null(input$continente) && input$continente != "Todos") {
        d <- d %>% filter(Continente == input$continente)
      }
      d
    })
    
    output$area <- renderPlot({
      d <- arq_filtrado() %>%
        count(Time, Cluster_Arquetipo) %>%
        complete(Time, Cluster_Arquetipo, fill = list(n = 0L))
      
      ggplot(d, aes(Time, n, fill = Cluster_Arquetipo)) +
        geom_area(alpha = 0.92) +
        geom_vline(xintercept = input$anio_sel, linetype = "dashed") +
        scale_fill_manual(values = pal, drop = FALSE, name = "Estadio") +
        labs(title = "Países por estadio demográfico",
             subtitle = "La línea discontinua marca el año elegido.",
             x = "Año", y = "Número de países") +
        tema_app()
    })
    
    output$titulo_tabla <- renderText(paste("Países por estadio en", input$anio_sel))
    
    output$tabla_estadios <- renderDT({
      d <- arq_filtrado() %>%
        filter(Time == input$anio_sel) %>%
        transmute(`País` = Location, Continente, Estadio = Cluster_Arquetipo,
                  `PC1 Madurez`    = round(PC1_Madurez, 2),
                  `PC2 Dinámica`   = round(PC2_Dinamica, 2),
                  `PC3 Estructura` = round(PC3_Estructura, 2)) %>%
        arrange(Estadio, `País`)
      datatable(d, rownames = FALSE, filter = "top", options = list(pageLength = 10))
    })
    
    output$tabla_centroides <- renderDT({
      cent <- datos$cent %>% mutate(across(where(is.numeric), ~ round(.x, 3)))
      datatable(cent, rownames = FALSE, options = list(dom = "t"))
    })
    
    # ---- 4. Transiciones -------------------------------------------------------
    trans_todas <- reactive({
      req(input$racha)
      transiciones_persistentes(datos$arq, input$racha)
    })
    
    trans <- reactive({
      t <- trans_todas()
      if (!is.null(input$continente_t) && input$continente_t != "Todos") {
        t <- t %>% filter(Continente == input$continente_t)
      }
      t
    })
    
    output$col_texto <- renderUI({
      t <- trans_todas() %>% filter(ISO3_code == "COL") %>% arrange(Anio)
      if (nrow(t) == 0) {
        return(tags$p("No cambia de estadio con esta regla de permanencia."))
      }
      tags$ul(lapply(seq_len(nrow(t)), function(i) {
        tags$li(sprintf("%d: %s a %s", t$Anio[i], as.character(t$Desde[i]), as.character(t$Hacia[i])))
      }))
    })
    
    output$hist_trans <- renderPlot({
      t <- trans()
      validate(need(nrow(t) > 0, "No hay transiciones con estos filtros."))
      t <- t %>% mutate(Decada = (Anio %/% 10) * 10)
      
      ggplot(t, aes(Decada, fill = Hacia)) +
        geom_bar(width = 8) +
        scale_fill_manual(values = pal, drop = FALSE, name = "Estadio de llegada") +
        labs(title = "Transiciones de estadio por década",
             subtitle = paste0("Permanencia mínima: ", input$racha, " años"),
             x = "Década", y = "Número de países") +
        tema_app()
    })
    
    output$tabla_trans <- renderDT({
      t <- trans() %>%
        transmute(`País` = Location, Continente, `Año` = Anio, Desde, Hacia) %>%
        arrange(`País`, `Año`)
      datatable(t, rownames = FALSE, filter = "top", options = list(pageLength = 10))
    })
  })
}