# ==============================================================================
# R/tema.R
# Identidad visual del proyecto: paleta accesible, tema ggplot2 y utilidades.
# Requiere: ggplot2, scales, tibble y R/config.R cargado antes.
# ------------------------------------------------------------------------------
# Principios de diseño
#  1. Accesible: paleta Okabe-Ito (segura para daltonismo) + viridis (mako)
#     para escalas continuas. Nunca se codifica información solo con color:
#     la proyección se marca además con zona sombreada y línea punteada.
#  2. Limpio: fondo marfil cálido, solo rejilla horizontal tenue, sin marcas
#     de eje, tipografía sans-serif, títulos alineados al borde del gráfico.
#  3. Legible: el título comunica el tema, el subtítulo explica cómo leer.
# ==============================================================================

# ---- Paleta ------------------------------------------------------------------
PAL <- list(
  
  # Okabe-Ito completa (referencia)
  okabe_ito = c(
    negro     = "#000000", naranja = "#E69F00", celeste = "#56B4E9",
    verde     = "#009E73", amarillo = "#F0E442", azul   = "#0072B2",
    bermellon = "#D55E00", purpura  = "#CC79A7"
  ),
  
  # Colores semánticos (usar siempre estos, no hexadecimales sueltos)
  estimacion = "#0072B2",   # azul   -> datos observados / estimados (<= 2023)
  proyeccion = "#E69F00",   # naranja-> proyección (>= 2024)
  acento     = "#D55E00",   # bermellón -> referencias y destacados
  texto      = "#1F2933",
  texto_suave = "#52606D",
  rejilla    = "#E4E7EB",
  fondo      = "#FBFAF7",
  
  # Orden recomendado para categorías (el amarillo va al final: poco contraste)
  cualitativa = c("#0072B2", "#E69F00", "#009E73", "#D55E00",
                  "#56B4E9", "#CC79A7", "#333333", "#F0E442"),
  
  # Regiones geográficas (VERIFICAR nombres exactos contra LocTypeName =
  # 'Geographic region' al iniciar la Fase 2)
  region = c(
    "Africa"                          = "#D55E00",
    "Asia"                            = "#E69F00",
    "Europe"                          = "#0072B2",
    "Latin America and the Caribbean" = "#009E73",
    "Northern America"                = "#56B4E9",
    "Oceania"                         = "#CC79A7"
  )
)

# ---- Escalas -----------------------------------------------------------------
scale_colour_dq_d <- function(...) ggplot2::scale_colour_manual(values = PAL$cualitativa, ...)
scale_color_dq_d  <- scale_colour_dq_d
scale_fill_dq_d   <- function(...) ggplot2::scale_fill_manual(values = PAL$cualitativa, ...)

scale_colour_dq_c <- function(...) ggplot2::scale_colour_viridis_c(option = "G", end = 0.95, ...)
scale_color_dq_c  <- scale_colour_dq_c
scale_fill_dq_c   <- function(...) ggplot2::scale_fill_viridis_c(option = "G", end = 0.95, ...)

# ---- Formato de números (respeta CFG$sep_decimal / CFG$sep_miles) -----------
fmt_num <- function(accuracy = 1, suffix = "") {
  scales::label_number(accuracy = accuracy, suffix = suffix,
                       big.mark = CFG$sep_miles, decimal.mark = CFG$sep_decimal)
}
fmt_miles_millones <- function(x) fmt_num(1, " mil M")(x)    # ej. 8 mil M
fmt_pct            <- function(x) fmt_num(1, " %")(x)

# ---- Tipografía --------------------------------------------------------------
# Por defecto "sans" (en Windows = Arial): funciona en cualquier dispositivo
# gráfico sin avisos. Para usar otra fuente instalada (p. ej. Inter, Roboto):
#   1) RStudio > Tools > Global Options > Graphics > Backend = "AGG"
#   2) options(dq.fuente = "Inter")   # antes de crear los gráficos
# Con el dispositivo por defecto de Windows, una fuente no registrada produce
# "font family not found in Windows font database".
fuente_dq <- function() getOption("dq.fuente", default = "sans")

# ---- Tema --------------------------------------------------------------------
# rejilla: "y" (horizontal, por defecto), "x", "xy" o "ninguna"
theme_dataquest <- function(base_size = 12,
                            base_family = fuente_dq(),
                            rejilla = c("y", "x", "xy", "ninguna")) {
  rejilla <- match.arg(rejilla)
  el_rej  <- ggplot2::element_line(colour = PAL$rejilla, linewidth = 0.4)
  
  t <- ggplot2::theme_minimal(base_size = base_size, base_family = base_family) +
    ggplot2::theme(
      text             = ggplot2::element_text(colour = PAL$texto),
      plot.background  = ggplot2::element_rect(fill = PAL$fondo, colour = NA),
      panel.background = ggplot2::element_rect(fill = PAL$fondo, colour = NA),
      panel.grid       = ggplot2::element_blank(),
      
      plot.title = ggplot2::element_text(face = "bold", size = ggplot2::rel(1.5),
                                         margin = ggplot2::margin(b = 5)),
      plot.subtitle = ggplot2::element_text(colour = PAL$texto_suave,
                                            size = ggplot2::rel(1.0), lineheight = 1.2,
                                            margin = ggplot2::margin(b = 14)),
      plot.caption = ggplot2::element_text(colour = PAL$texto_suave,
                                           size = ggplot2::rel(0.8), hjust = 0,
                                           margin = ggplot2::margin(t = 14)),
      plot.title.position   = "plot",
      plot.caption.position = "plot",
      plot.margin = ggplot2::margin(18, 22, 12, 18),
      
      axis.title = ggplot2::element_text(colour = PAL$texto_suave, size = ggplot2::rel(0.9)),
      axis.text  = ggplot2::element_text(colour = PAL$texto_suave, size = ggplot2::rel(0.9)),
      axis.ticks = ggplot2::element_blank(),
      axis.line.x = ggplot2::element_line(colour = "#9AA5B1", linewidth = 0.4),
      
      legend.position      = "top",
      legend.justification = "left",
      legend.title = ggplot2::element_text(face = "bold", size = ggplot2::rel(0.9)),
      legend.text  = ggplot2::element_text(size = ggplot2::rel(0.9)),
      legend.key   = ggplot2::element_rect(fill = NA, colour = NA),
      
      strip.text = ggplot2::element_text(face = "bold", hjust = 0,
                                         margin = ggplot2::margin(b = 6)),
      panel.spacing = ggplot2::unit(1.2, "lines")
    )
  
  if (rejilla %in% c("y", "xy")) t <- t + ggplot2::theme(panel.grid.major.y = el_rej)
  if (rejilla %in% c("x", "xy")) t <- t + ggplot2::theme(panel.grid.major.x = el_rej)
  t
}

# ---- Capa de "zona de proyección" -------------------------------------------
# Añade fondo sombreado + línea punteada desde el último año estimado, y
# etiquetas "Estimación" / "Proyección". Va PRIMERA en el ggplot (queda al fondo).
# Para gráficos con eje x de años (numérico).
capa_proyeccion <- function(corte = CFG$ultimo_anio_estimado,
                            etiquetas = TRUE, y_etiqueta = Inf) {
  capas <- list(
    ggplot2::annotate("rect", xmin = corte + 0.5, xmax = Inf, ymin = -Inf, ymax = Inf,
                      fill = PAL$proyeccion, alpha = 0.08),
    ggplot2::geom_vline(xintercept = corte + 0.5, linetype = "dashed",
                        colour = PAL$proyeccion, linewidth = 0.5)
  )
  if (etiquetas) {
    capas <- c(capas, list(
      ggplot2::annotate("text", x = corte - 1.5, y = y_etiqueta, label = "Estimación",
                        hjust = 1, vjust = 1.9, size = 3.5, fontface = "bold",
                        colour = PAL$estimacion),
      ggplot2::annotate("text", x = corte + 2.5, y = y_etiqueta,
                        label = "Proyección (variante Medium)",
                        hjust = 0, vjust = 1.9, size = 3.5, fontface = "bold",
                        colour = "#B87800")
    ))
  }
  capas
}

# ---- Guardado de figuras -----------------------------------------------------
guardar_fig <- function(plot, nombre, ancho = 9, alto = 5.5, dir = CFG$dir_figs) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  archivo <- file.path(dir, paste0(nombre, ".png"))
  # ragg (si está instalado) renderiza mejor el texto y respeta fuentes del sistema
  dispositivo <- if (requireNamespace("ragg", quietly = TRUE)) ragg::agg_png else "png"
  ggplot2::ggsave(archivo, plot, width = ancho, height = alto, units = "in",
                  dpi = CFG$fig_dpi, bg = PAL$fondo, device = dispositivo)
  message("Figura guardada: ", archivo)
  invisible(archivo)
}

# ---- Vista previa de la paleta (verificación visual) ------------------------
previsualizar_paleta <- function() {
  df <- tibble::tibble(
    nombre = names(PAL$okabe_ito),
    hex    = unname(PAL$okabe_ito),
    x      = seq_along(PAL$okabe_ito)
  )
  ggplot2::ggplot(df, ggplot2::aes(x, 1, fill = hex)) +
    ggplot2::geom_tile(width = 0.92, height = 0.7) +
    ggplot2::geom_text(ggplot2::aes(label = nombre), vjust = 3.0, size = 3.4,
                       colour = PAL$texto) +
    ggplot2::geom_text(ggplot2::aes(label = hex), vjust = 4.6, size = 3,
                       colour = PAL$texto_suave) +
    ggplot2::scale_fill_identity() +
    ggplot2::scale_y_continuous(limits = c(0.2, 1.5)) +
    ggplot2::labs(title = "Paleta Okabe-Ito",
                  subtitle = "Segura para daltonismo. Azul = estimación, naranja = proyección, bermellón = acento.") +
    theme_dataquest(rejilla = "ninguna") +
    ggplot2::theme(axis.text = ggplot2::element_blank(),
                   axis.title = ggplot2::element_blank(),
                   axis.line = ggplot2::element_blank())
}