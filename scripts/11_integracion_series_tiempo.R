# ==============================================================================
# ASA DataQuest 2026 - WPP2024
# Script 11: Integración del módulo de series de tiempo (script 10) con el resto del flujo
# ------------------------------------------------------------------------------
# NO reajusta ningún modelo ni modifica el trabajo del script 10. Solo LEE sus salidas y:
#   1. Concilia la relación de soporte (RS) del script 10 (archivo del portal de datos de la
#      ONU) con el PSR65 calculado en el script 03 (población por edad simple, E1).
#   2. Aplica la regla D16 del plan: el pronóstico propio "discrepa" de la ONU solo si cae
#      FUERA de la banda oficial del 80 % [min, max] de (Lower 80 PI, Upper 80 PI) (D14).
#      Disponible para los indicadores que traen intervalos en OtherVariants (no LE60, no RS).
#   3. Triangula el año en que la RS baja de 3 para Colombia: ONU (script 03), DANE (script 03),
#      propio (script 10) y su intervalo, y resume la comparación en el universo (D12).
#   4. Figuras con el tema del proyecto.
#
# Entradas : salidas del script 10 (carpeta CFG$dir_out o "R/time series")
#            data/clean/wpp_paises_medium_suppl.parquet, un_estructura_edad.parquet,
#            dane_estructura_edad.rds ; output/tablas/03_cruces_umbrales_colombia.csv
#            OtherVariants (raw)
# Salidas  : output/tablas/11_*.csv ; output/figuras/11_*.png
# Ejecutar de arriba hacia abajo, desde la raíz del proyecto, DESPUÉS del script 10.
# ==============================================================================

# ---- 0. Entorno --------------------------------------------------------------
if (!file.exists("R/config.R")) stop("Abre el proyecto (.Rproj) o fija setwd() en la raíz.")
paquetes <- c("DBI", "duckdb", "dplyr", "tidyr", "glue", "tibble", "ggplot2", "scales")
faltan <- setdiff(paquetes, rownames(installed.packages()))
if (length(faltan) > 0) install.packages(faltan)
invisible(lapply(paquetes, library, character.only = TRUE))
source("R/config.R",      encoding = "UTF-8")
source("R/utils_datos.R", encoding = "UTF-8")
source("R/tema.R",        encoding = "UTF-8")
crear_directorios()

PAIS      <- "COL"
UMBRAL_RS <- 3                                   # el mismo del script 10
VARS_BANDA <- c("MedianAgePop", "TFR", "LEx", "LE65", "CBR")   # candidatas con banda oficial
BLOQUES <- list("2024-2050" = 2024:2050, "2051-2075" = 2051:2075, "2076-2100" = 2076:2100)

DIR_TS <- if (!is.null(CFG$dir_out)) CFG$dir_out else "R/time series"
ts_f <- function(f) file.path(DIR_TS, f)
for (f in c("Proyecciones_Propias_vs_ONU_largo.csv", "puntos_criticos_RS.csv",
            "resumen_validacion.csv", "historico_largo.csv")) {
  verificar(file.exists(ts_f(f)), paste("Encontrado:", f),
            paste("Falta", ts_f(f), "-> ejecuta primero el script 10 (series de tiempo)."))
}

con <- conectar_duckdb(if (exists("con")) con else NULL)
dbExecute(con, glue("CREATE OR REPLACE VIEW wpp AS
                     SELECT * FROM read_parquet('{file.path(CFG$dir_clean, CFG$f_parquet)}')"))
crear_vista_csv(con, "other_raw", CFG$f_other)

propio <- read.csv(ts_f("Proyecciones_Propias_vs_ONU_largo.csv"), stringsAsFactors = FALSE) |> as_tibble()
crit   <- read.csv(ts_f("puntos_criticos_RS.csv"),                stringsAsFactors = FALSE) |> as_tibble()
histo  <- read.csv(ts_f("historico_largo.csv"),                   stringsAsFactors = FALSE) |> as_tibble()

universo <- dbGetQuery(con, glue("
  SELECT ISO3_code FROM wpp
  WHERE Time = {CFG$ultimo_anio_estimado} AND TPopulation1July >= {CFG$umbral_universo_miles}"))$ISO3_code
cat("Países en el módulo de series de tiempo:", n_distinct(propio$ISO3_code),
    "| universo D12:", length(universo),
    "| universo dentro del módulo:", sum(universo %in% propio$ISO3_code), "\n")


# ---- 1. Conciliar RS: portal (script 10) frente a PSR65 (script 03) ----------
seccion("1. CONCILIACIÓN DE LA RELACIÓN DE SOPORTE (dos fuentes de la ONU)")

psr03 <- dbGetQuery(con, glue("
  SELECT w.ISO3_code, e.Time, e.psr65
  FROM read_parquet('{file.path(CFG$dir_clean, 'un_estructura_edad.parquet')}') e
  JOIN wpp w ON e.LocID = w.LocID AND e.Time = w.Time
  WHERE e.Time > {CFG$ultimo_anio_estimado}")) |> as_tibble()

conc <- propio |> filter(Variable == "RS") |>
  select(ISO3_code, Time, rs_portal = ONU) |>
  inner_join(psr03, by = c("ISO3_code", "Time")) |>
  mutate(dif_rel = (rs_portal - psr65) / psr65)

resumen_conc <- conc |> mutate(universo = ISO3_code %in% universo) |>
  group_by(universo) |>
  summarise(filas = n(), mediana_abs = median(abs(dif_rel), na.rm = TRUE),
            p99_abs = quantile(abs(dif_rel), 0.99, na.rm = TRUE),
            max_abs = max(abs(dif_rel), na.rm = TRUE), .groups = "drop")
ver(resumen_conc)
cat("\nDiez mayores diferencias relativas:\n")
ver(conc |> arrange(desc(abs(dif_rel))) |> head(10) |>
      mutate(across(c(rs_portal, psr65), ~ round(.x, 3)), dif_rel = round(dif_rel, 4)))
verificar(resumen_conc$mediana_abs[resumen_conc$universo] < 0.01,
          "Las dos fuentes de RS coinciden (mediana |dif. relativa| < 1 % en el universo).",
          "Las dos fuentes de RS difieren más de 1 % (mediana): revisar fecha de referencia o definición.",
          fatal = FALSE)
write.csv(resumen_conc, file.path(CFG$dir_tablas, "11_conciliacion_rs.csv"), row.names = FALSE)


# ---- 2. Regla D16: ¿el pronóstico propio cae dentro de la banda oficial del 80 %? --
seccion("2. PRONÓSTICO PROPIO FRENTE A LA BANDA OFICIAL DEL 80 % (D16)")

cols_other <- dbGetQuery(con, "DESCRIBE other_raw")$column_name
vars_ok <- intersect(VARS_BANDA, cols_other)
cat("Indicadores con banda oficial disponibles:", paste(vars_ok, collapse = ", "), "\n")
cat("Sin banda oficial (no se evalúan con D16): LE60 (solo en el suplemento), IRG y RS (derivados).\n")

banda <- bind_rows(lapply(vars_ok, function(v) {
  dbGetQuery(con, glue("
    SELECT ISO3_code, Time, Variant, \"{v}\" AS valor
    FROM other_raw
    WHERE Variant IN ('Lower 80 PI', 'Upper 80 PI') AND {SQL_ES_PAIS}
      AND Time BETWEEN {CFG$ultimo_anio_estimado + 1} AND {CFG$ultimo_anio_analisis}")) |>
    mutate(Variable = v)
})) |> as_tibble() |>
  group_by(ISO3_code, Time, Variable) |>
  summarise(lo_onu = min(valor), hi_onu = max(valor), .groups = "drop")   # D14: [mín, máx]

d16 <- propio |> filter(Variable %in% vars_ok) |>
  inner_join(banda, by = c("ISO3_code", "Time", "Variable")) |>
  mutate(posicion = case_when(Propia < lo_onu ~ "Debajo de la banda",
                              Propia > hi_onu ~ "Encima de la banda",
                              TRUE ~ "Dentro de la banda"),
         bloque = cut(Time, c(2023, 2050, 2075, 2100), labels = names(BLOQUES)),
         en_universo = ISO3_code %in% universo)

resumen_d16 <- d16 |> filter(en_universo) |>
  count(Variable, bloque, posicion) |>
  group_by(Variable, bloque) |> mutate(pct = round(100 * n / sum(n), 1)) |> ungroup()
cat("\nUniverso (161 países): % de país-año según la posición del pronóstico propio\n")
ver(resumen_d16 |> select(-n) |> pivot_wider(names_from = posicion, values_from = pct, values_fill = 0))
write.csv(resumen_d16, file.path(CFG$dir_tablas, "11_d16_posicion_vs_banda80.csv"), row.names = FALSE)

cat("\nColombia (2050 y 2100):\n")
ver(d16 |> filter(ISO3_code == PAIS, Time %in% c(2050, 2100)) |>
      transmute(Variable, Time, propio = round(Propia, 2), lo_onu = round(lo_onu, 2),
                onu_medium = round(ONU, 2), hi_onu = round(hi_onu, 2), posicion))

p_d16 <- resumen_d16 |>
  mutate(posicion = factor(posicion, levels = c("Debajo de la banda", "Dentro de la banda", "Encima de la banda"))) |>
  ggplot(aes(bloque, pct, fill = posicion)) +
  geom_col(width = 0.75) +
  facet_wrap(~ Variable, nrow = 1) +
  scale_fill_manual(values = c("Debajo de la banda" = PAL$okabe_ito[["bermellon"]],
                               "Dentro de la banda" = "#B8C0C8",
                               "Encima de la banda" = PAL$okabe_ito[["azul"]]), name = NULL) +
  scale_y_continuous(labels = fmt_num(1, " %"), expand = expansion(mult = c(0, 0.02))) +
  labs(title = "Pronóstico propio frente a la banda oficial del 80 % de la ONU",
       subtitle = paste0("Porcentaje de país-año por posición del pronóstico propio. Universo de ",
                         length(universo), " países. Un pronóstico \"discrepa\" solo si cae fuera de la banda (D16)."),
       x = NULL, y = NULL,
       caption = "Fuentes: UN WPP 2024 (Medium y OtherVariants, intervalos Lower/Upper 80 PI); pronóstico propio: script 10.") +
  theme_dataquest() + theme(axis.text.x = element_text(angle = 30, hjust = 1))
print(p_d16); guardar_fig(p_d16, "11_pronostico_propio_vs_banda80", ancho = 11, alto = 5)


# ---- 3. Año en que la RS baja de 3: ONU, DANE y propio ------------------------
seccion("3. AÑO EN QUE LA RELACIÓN DE SOPORTE BAJA DE 3: TRIANGULACIÓN PARA COLOMBIA")

cruces03 <- read.csv(file.path(CFG$dir_tablas, "03_cruces_umbrales_colombia.csv"), stringsAsFactors = FALSE) |>
  as_tibble() |> filter(definicion == "15-64 / 65+", umbral == UMBRAL_RS)
c_col <- crit |> filter(ISO3_code == PAIS)

triang <- bind_rows(
  tibble(fuente = "DANE (script 03)",         regla = "3 años seguidos bajo el umbral",  anio = cruces03$anio_cruce[cruces03$fuente == "DANE"]),
  tibble(fuente = "ONU Medium (script 03)",   regla = "3 años seguidos bajo el umbral",  anio = cruces03$anio_cruce[cruces03$fuente == "ONU"]),
  tibble(fuente = "ONU Medium (script 10)",   regla = "se mantiene bajo el umbral hasta 2100", anio = c_col$Critico_ONU),
  tibble(fuente = "Propio, central (script 10)", regla = "se mantiene bajo el umbral hasta 2100", anio = c_col$Critico_Propia),
  tibble(fuente = "Propio, límite temprano (IC95)", regla = "banda inferior", anio = c_col$Critico_IC_temprano),
  tibble(fuente = "Propio, límite tardío (IC95)",   regla = "banda superior (NA = no cruza antes de 2100)", anio = c_col$Critico_IC_tardio)
)
cat("Colombia, RS = 15-64 / 65+ < ", UMBRAL_RS, ":\n", sep = ""); ver(triang)
write.csv(triang, file.path(CFG$dir_tablas, "11_triangulacion_colombia_rs3.csv"), row.names = FALSE)
cat("\nLa ONU coincide entre scripts si 03 y 10 dan el mismo año (las dos reglas son equivalentes aquí).\n")

# Universo: diferencia propio - ONU en el año crítico
dif_u <- crit |> filter(ISO3_code %in% universo) |>
  mutate(dif = Critico_Propia - Critico_ONU)
resumen_crit <- tibble(
  paises_universo        = nrow(dif_u),
  cruzan_propio          = sum(!is.na(dif_u$Critico_Propia)),
  cruzan_onu             = sum(!is.na(dif_u$Critico_ONU)),
  cruzan_ambos           = sum(!is.na(dif_u$dif)),
  mediana_dif_anios      = median(dif_u$dif, na.rm = TRUE),
  prop_dentro_5_anios    = round(mean(abs(dif_u$dif) <= 5, na.rm = TRUE), 3),
  prop_propio_antes      = round(mean(dif_u$dif < 0, na.rm = TRUE), 3))
cat("\nUniverso (propio - ONU, años; negativo = el propio cruza antes):\n"); ver(resumen_crit)
write.csv(resumen_crit, file.path(CFG$dir_tablas, "11_resumen_anio_critico_universo.csv"), row.names = FALSE)


# ---- 4. Figura: RS de Colombia con tres fuentes --------------------------------
seccion("4. FIGURA: RELACIÓN DE SOPORTE DE COLOMBIA")

dane <- readRDS(file.path(CFG$dir_clean, "dane_estructura_edad.rds")) |>
  transmute(Time = anio, valor = psr65) |> filter(Time >= 2018)
rs_p <- propio |> filter(ISO3_code == PAIS, Variable == "RS")
rs_h <- histo  |> filter(ISO3_code == PAIS, Variable == "RS")

g <- function(f) triang$anio[triang$fuente == f]
txt_anios <- sprintf("propio %s, ONU %s, DANE %s", g("Propio, central (script 10)"),
                     g("ONU Medium (script 10)"), g("DANE (script 03)"))
p_rs <- ggplot() +
  capa_proyeccion(etiquetas = FALSE) +
  geom_hline(yintercept = UMBRAL_RS, linetype = "dotted", colour = PAL$texto_suave, linewidth = 0.5) +
  geom_ribbon(data = rs_p, aes(Time, ymin = lo95, ymax = hi95), fill = PAL$acento, alpha = 0.12) +
  geom_line(data = rs_h, aes(Time, Valor), colour = PAL$estimacion, linewidth = 1.1) +
  geom_line(data = rs_p, aes(Time, ONU,    colour = "ONU Medium"),         linewidth = 1.1) +
  geom_line(data = rs_p, aes(Time, Propia, colour = "Pronóstico propio"),  linewidth = 1.1) +
  geom_line(data = dane, aes(Time, valor,  colour = "DANE (2018-2070)"),   linewidth = 1.1) +
  scale_colour_manual(values = c("ONU Medium" = PAL$estimacion, "Pronóstico propio" = PAL$acento,
                                 "DANE (2018-2070)" = PAL$okabe_ito[["verde"]]), name = NULL) +
  scale_x_continuous(breaks = seq(1950, 2100, 25), expand = expansion(mult = c(0.01, 0.02))) +
  scale_y_continuous(labels = fmt_num(1), limits = c(0, NA), expand = expansion(mult = c(0, 0.05))) +
  labs(title = "Relación de soporte de Colombia: tres proyecciones, un mismo rumbo",
       subtitle = paste0("Personas de 15-64 por cada persona de 65+. Línea punteada: referencia de ", UMBRAL_RS,
                         " (escenario, no estándar). Banda: IC95 del pronóstico propio.\n",
                         "Año en que baja de ", UMBRAL_RS, ": ", txt_anios,
                         ". El soporte demográfico no mide la sostenibilidad de un sistema pensional."),
       x = NULL, y = "Personas en edad de trabajar por persona mayor",
       caption = paste0("Fuentes: UN WPP 2024 (Medium); DANE (julio de 2025); pronóstico propio (script 10, horizonte ",
                        "validado hasta ~33 años; más allá es ilustrativo).")) +
  theme_dataquest()
print(p_rs); guardar_fig(p_rs, "11_rs_colombia_tres_fuentes", ancho = 10, alto = 5.8)

cat("\nSiguiente paso: copiar a la app los CSV del script 10 (ver app/app.R) y, si se usa, clusters.csv.\n")
# dbDisconnect(con, shutdown = TRUE)
