# ==============================================================================
# ASA DataQuest 2026 - WPP2024
# Script 00: ETL, validación y exploración inicial (Fase 0)
# ------------------------------------------------------------------------------
# Ejecutar de ARRIBA HACIA ABAJO desde la raíz del proyecto (.Rproj abierto).
# Las vistas SQL dependen del orden de las secciones.
#
# Entradas : data/raw/*  (4 archivos, nunca se modifican)
# Salidas  : data/clean/wpp_paises_medium_suppl.parquet   (tabla maestra)
#            data/clean/diccionario_indicadores.rds
#            data/clean/resumen_fase0.rds
#            output/tablas/00_*.csv
#            output/figuras/00_*.png
#
# Decisiones que implementa (ver DECISIONES.md):
#   D1 países = ISO3 no nulo | D2 estimación <= 2023 | D3 análisis hasta 2100
#   D4 Holy See sin suplemento | D5 agregados solo de referencia
#   D6 DoublingTime censurado (no se imputa) | D7 tolerancia de nacimientos 0.0011
# ==============================================================================


# ---- 0. Entorno --------------------------------------------------------------
if (!file.exists("R/config.R")) {
  stop("No se encuentra R/config.R. Abre el proyecto (.Rproj) o fija el ",
       "directorio de trabajo en la raíz del proyecto con setwd().")
}

paquetes <- c("DBI", "duckdb", "dplyr", "tidyr", "ggplot2", "glue", "scales", "tibble")
faltan <- setdiff(paquetes, rownames(installed.packages()))
if (length(faltan) > 0) install.packages(faltan)
invisible(lapply(paquetes, library, character.only = TRUE))

source("R/config.R",      encoding = "UTF-8")
source("R/utils_datos.R", encoding = "UTF-8")
source("R/tema.R",        encoding = "UTF-8")

crear_directorios()
set.seed(CFG$semilla)


# ---- 1. Conexión duckdb y vistas sobre los archivos crudos -------------------
# Las vistas NO cargan los datos en RAM: duckdb lee los archivos bajo demanda.
# Nota: duckdb NO interpreta "NA" como nulo (pandas sí), así que Namibia ("NAM")
# no se ve afectada. Las celdas vacías sí se leen como NULL.
con <- conectar_duckdb(if (exists("con")) con else NULL)

crear_vista_csv(con, "medium_raw", CFG$f_medium)
crear_vista_csv(con, "other_raw",  CFG$f_other)
crear_vista_csv(con, "suppl_raw",  CFG$f_suppl)

notes <- read.csv(ruta(CFG$f_notes), fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE)


# ---- 2. Esquemas -------------------------------------------------------------
seccion("2. ESQUEMAS")

esq_medium <- dbGetQuery(con, "DESCRIBE medium_raw")
esq_other  <- dbGetQuery(con, "DESCRIBE other_raw")
esq_suppl  <- dbGetQuery(con, "DESCRIBE suppl_raw")

cat("Columnas -> Medium:", nrow(esq_medium), "| OtherVariants:", nrow(esq_other),
    "| Suplemento:", nrow(esq_suppl), "\n")

cols_id <- c("SortOrder", "LocID", "Notes", "ISO3_code", "ISO2_code", "SDMX_code",
             "LocTypeID", "LocTypeName", "ParentID", "Location", "VarID",
             "Variant", "Time")
cols_ind   <- setdiff(esq_medium$column_name, cols_id)
vars_suppl <- c("BirthsMale", "BirthsFemale", "LE60", "LE60Male", "LE60Female")

verificar(length(cols_ind) == 54,
          "54 indicadores detectados en Medium.",
          paste("Se esperaban 54 indicadores y hay", length(cols_ind)))
verificar(length(intersect(vars_suppl, esq_medium$column_name)) == 0,
          "Las 5 variables del suplemento no están en Medium (como documenta la guía).",
          "Alguna variable del suplemento aparece en Medium: revisar la guía.")
verificar(setequal(esq_suppl$column_name,
                   c("LocID", "ISO3_code", "Location", "Time", vars_suppl)),
          "El suplemento tiene exactamente las 9 columnas documentadas.",
          "Las columnas del suplemento no coinciden con la documentación.",
          fatal = FALSE)


# ---- 3. Validaciones estructurales del archivo Medium ------------------------
seccion("3. VALIDACIONES DE ESTRUCTURA (MEDIUM)")

dim_medium <- dbGetQuery(con, "
  SELECT COUNT(*) AS filas, COUNT(DISTINCT LocID) AS ubicaciones,
         MIN(Time) AS t_min, MAX(Time) AS t_max
  FROM medium_raw")
ver(dim_medium)
verificar(with(dim_medium, filas == 84360 && ubicaciones == 555 &&
                 t_min == 1950 && t_max == 2101),
          "84,360 filas, 555 ubicaciones, años 1950-2101 (según la guía).",
          "Las dimensiones de Medium no coinciden con la guía.", fatal = FALSE)

variantes <- dbGetQuery(con, "SELECT Variant, COUNT(*) AS n FROM medium_raw GROUP BY 1")
verificar(nrow(variantes) == 1 && variantes$Variant == "Medium",
          "Variante única: 'Medium'.", "Medium contiene más de una variante.")

dup <- dbGetQuery(con, "
  SELECT COUNT(*) AS n_dup FROM (
    SELECT LocID, Time FROM medium_raw GROUP BY 1, 2 HAVING COUNT(*) > 1)")
verificar(dup$n_dup == 0, "Llave (LocID, Time) única.", "Hay llaves duplicadas.")

# LocTypeName NO es confiable por sí solo: 234 ubicaciones lo tienen en NA
tipos <- dbGetQuery(con, glue("
  SELECT LocTypeName,
         COUNT(DISTINCT LocID) AS ubicaciones,
         COUNT(DISTINCT CASE WHEN {SQL_ES_PAIS} THEN LocID END) AS con_iso3
  FROM medium_raw GROUP BY 1 ORDER BY ubicaciones DESC"))
ver(tipos)


# ---- 4. Regla de países: ISO3_code no nulo (D1, D5) --------------------------
seccion("4. AISLAMIENTO DE PAÍSES (ISO3_code no nulo)")

dbExecute(con, glue("CREATE OR REPLACE VIEW medium_paises AS
                     SELECT * FROM medium_raw WHERE {SQL_ES_PAIS}"))
dbExecute(con, glue("CREATE OR REPLACE VIEW medium_agregados AS
                     SELECT * FROM medium_raw WHERE NOT ({SQL_ES_PAIS})"))

n_paises <- dbGetQuery(con, "SELECT COUNT(DISTINCT LocID) n FROM medium_paises")$n
n_agreg  <- dbGetQuery(con, "SELECT COUNT(DISTINCT LocID) n FROM medium_agregados")$n
verificar(n_paises == 237 && n_agreg == 318 && n_paises + n_agreg == 555,
          "237 países/áreas + 318 agregados = 555 ubicaciones.",
          paste("Conteo inesperado: países =", n_paises, "| agregados =", n_agreg),
          fatal = FALSE)

# Prueba anti doble-conteo: suma de países vs. fila 'World'
chk_mundo <- dbGetQuery(con, "
  WITH p AS (SELECT Time, SUM(TPopulation1July) AS suma_paises
             FROM medium_paises GROUP BY Time),
       w AS (SELECT Time, TPopulation1July AS mundo
             FROM medium_agregados WHERE Location = 'World')
  SELECT p.Time, p.suma_paises, w.mundo,
         ROUND(100 * (p.suma_paises - w.mundo) / w.mundo, 4) AS dif_pct
  FROM p JOIN w USING (Time) ORDER BY Time")

dif_max <- max(abs(chk_mundo$dif_pct), na.rm = TRUE)
verificar(dif_max < 0.01,
          sprintf("Suma de países = fila 'World' (diferencia máx. %.4f %%): sin doble conteo.", dif_max),
          "La suma de países no coincide con 'World': posible doble conteo.")
cat("  Años sin comparación (NA):",
    paste(chk_mundo$Time[is.na(chk_mundo$dif_pct)], collapse = ", "), "\n")


# ---- 5. Diagnóstico del año 2101 (D3) ----------------------------------------
seccion("5. AÑO 2101")

pobl_2101 <- dbGetQuery(con, glue("
  SELECT {sql_contar_no_nulos(cols_ind)} FROM medium_paises WHERE Time = 2101")) |>
  pivot_longer(everything(), names_to = "indicador", values_to = "n_con_dato") |>
  filter(n_con_dato > 0)
ver(pobl_2101)
verificar(identical(pobl_2101$indicador, "TPopulation1Jan"),
          "En 2101 solo existe TPopulation1Jan -> el análisis llega hasta 2100 (D3).",
          "2101 trae más indicadores de lo esperado: revisar D3.", fatal = FALSE)


# ---- 6. Suplemento: validación (D4, D7) --------------------------------------
seccion("6. SUPLEMENTO (Births by sex + LE60)")

dim_suppl <- dbGetQuery(con, "
  SELECT COUNT(*) AS filas, COUNT(DISTINCT LocID) AS ubicaciones,
         MIN(Time) AS t_min, MAX(Time) AS t_max FROM suppl_raw")
ver(dim_suppl)
verificar(with(dim_suppl, filas == 35636 && ubicaciones == 236 &&
                 t_min == 1950 && t_max == 2100),
          "Suplemento: 35,636 filas, 236 países, 1950-2100 (según su documentación).",
          "Dimensiones del suplemento distintas a lo documentado.", fatal = FALSE)

sin_suppl <- dbGetQuery(con, "
  SELECT DISTINCT LocID, ISO3_code, Location FROM medium_paises
  WHERE LocID NOT IN (SELECT DISTINCT LocID FROM suppl_raw)")
verificar(identical(sin_suppl$ISO3_code, "VAT"),
          "Único país sin suplemento: Holy See (VAT) -> D4.",
          "Hay países sin suplemento distintos de Holy See.")

# Births_M + Births_F debe igualar Births con tolerancia 0.0011 (D7)
chk_births <- dbGetQuery(con, glue("
  SELECT COUNT(*) AS n_comparadas,
         MAX(ABS((s.BirthsMale + s.BirthsFemale) - m.Births)) AS dif_max,
         SUM(CASE WHEN ABS((s.BirthsMale + s.BirthsFemale) - m.Births) > {CFG$tol_births}
                  THEN 1 ELSE 0 END) AS n_fuera_tol
  FROM suppl_raw s JOIN medium_paises m USING (LocID, Time)"))
ver(chk_births)
verificar(chk_births$n_fuera_tol == 0,
          sprintf("Nacimientos por sexo coherentes con Births (dif. máx. %.4f, tolerancia %.4f).",
                  chk_births$dif_max, CFG$tol_births),
          "Hay filas con Births_M + Births_F fuera de tolerancia.")

# LE60 (ambos sexos) debe estar entre LE60Male y LE60Female
chk_le60 <- dbGetQuery(con, "
  SELECT COUNT(*) AS n,
         SUM(CASE WHEN LE60 < LEAST(LE60Male, LE60Female) - 1e-9
                    OR LE60 > GREATEST(LE60Male, LE60Female) + 1e-9
                  THEN 1 ELSE 0 END) AS n_incoherentes
  FROM suppl_raw")
verificar(chk_le60$n_incoherentes == 0,
          "LE60 siempre entre LE60Male y LE60Female.",
          "Hay valores de LE60 incoherentes con los de cada sexo.")


# ---- 7. Vista maestra país-año (Medium + suplemento, hasta 2100) -------------
seccion("7. VISTA MAESTRA wpp_paises")

# LEFT JOIN: Medium manda. Se recorta a CFG$ultimo_anio_analisis (D3).
dbExecute(con, glue("
  CREATE OR REPLACE VIEW wpp_paises AS
  SELECT m.*,
         s.BirthsMale, s.BirthsFemale, s.LE60, s.LE60Male, s.LE60Female,
         CASE WHEN m.Time <= {CFG$ultimo_anio_estimado}
              THEN 'Estimación' ELSE 'Proyección' END AS tipo_dato
  FROM medium_paises m
  LEFT JOIN suppl_raw s ON m.LocID = s.LocID AND m.Time = s.Time
  WHERE m.Time <= {CFG$ultimo_anio_analisis}"))

n_wpp <- dbGetQuery(con, "SELECT COUNT(*) n FROM wpp_paises")$n
verificar(n_wpp == 237 * (CFG$ultimo_anio_analisis - CFG$primer_anio + 1),
          paste0("wpp_paises: ", format(n_wpp, big.mark = ","), " filas = 237 países x 151 años."),
          paste("wpp_paises tiene", n_wpp, "filas; se esperaban 35,787."))

chk_le60_na <- dbGetQuery(con, "
  SELECT Location, COUNT(*) AS n_na FROM wpp_paises WHERE LE60 IS NULL GROUP BY Location")
verificar(identical(chk_le60_na$Location, "Holy See") && chk_le60_na$n_na == 151,
          "LE60 faltante solo en Holy See (151 filas) -> D4.",
          "LE60 tiene faltantes en países distintos de Holy See.")


# ---- 8. Valores faltantes (sobre la vista maestra) ---------------------------
seccion("8. VALORES FALTANTES (países, 1950-2100)")

na_tab <- dbGetQuery(con, glue("SELECT {sql_contar_nulos(cols_ind)} FROM wpp_paises")) |>
  pivot_longer(everything(), names_to = "indicador", values_to = "n_na") |>
  mutate(pct_na = round(100 * n_na / n_wpp, 2)) |>
  arrange(desc(n_na))

ver(na_tab |> filter(n_na > 0))
verificar(identical(na_tab$indicador[na_tab$n_na > 0], "DoublingTime"),
          "52 de 54 indicadores completos; el único con faltantes es DoublingTime (D6).",
          "Hay indicadores con faltantes distintos de DoublingTime.")
write.csv(na_tab, file.path(CFG$dir_tablas, "00_faltantes_por_indicador.csv"), row.names = FALSE)


# ---- 9. DoublingTime: censura estructural (D6) -------------------------------
seccion("9. DOUBLINGTIME: CENSURA ESTRUCTURAL")

censura <- dbGetQuery(con, glue("
  SELECT COUNT(*) AS n_filas,
         SUM(CASE WHEN DoublingTime IS NULL THEN 1 ELSE 0 END) AS n_na,
         SUM(CASE WHEN PopGrowthRate <= {CFG$umbral_doubling} AND DoublingTime IS NOT NULL
                  THEN 1 ELSE 0 END) AS dato_bajo_umbral,
         SUM(CASE WHEN PopGrowthRate >  {CFG$umbral_doubling} AND DoublingTime IS NULL
                  THEN 1 ELSE 0 END) AS na_sobre_umbral,
         MAX(PopGrowthRate) FILTER (WHERE DoublingTime IS NULL)     AS max_crec_con_na,
         MIN(PopGrowthRate) FILTER (WHERE DoublingTime IS NOT NULL) AS min_crec_con_dato
  FROM wpp_paises"))
ver(censura)
cat(sprintf("  Mayor crecimiento con DoublingTime = NA : %s %%\n",
            format(censura$max_crec_con_na, digits = 8)))
cat(sprintf("  Menor crecimiento con DoublingTime dato : %s %%\n",
            format(censura$min_crec_con_dato, digits = 8)))
cat(sprintf("  Filas censuradas: %s de %s (%.1f %%)\n",
            format(censura$n_na, big.mark = ","), format(censura$n_filas, big.mark = ","),
            100 * censura$n_na / censura$n_filas))

verificar(censura$dato_bajo_umbral == 0 && censura$na_sobre_umbral == 0,
          sprintf("DoublingTime existe si y solo si el crecimiento supera %.1f %% anual.",
                  CFG$umbral_doubling),
          "El umbral de censura de DoublingTime no es limpio: revisar D6.", fatal = FALSE)


# ---- 10. OtherVariants: perfil sin cargarlo completo -------------------------
seccion("10. OTHERVARIANTS (perfil vía SQL)")

# 10.1 Cobertura por variante
var_tab <- dbGetQuery(con, glue("
  SELECT Variant, COUNT(*) AS filas,
         COUNT(DISTINCT LocID) AS ubicaciones,
         COUNT(DISTINCT CASE WHEN {SQL_ES_PAIS} THEN LocID END) AS paises,
         MIN(Time) AS t_min, MAX(Time) AS t_max
  FROM other_raw GROUP BY 1 ORDER BY 1"))
ver(var_tab)
verificar(nrow(var_tab) == 18, "18 variantes distintas.",
          paste("Hay", nrow(var_tab), "variantes; se esperaban 18."), fatal = FALSE)

# 10.2 ¿Qué indicadores traen datos en cada variante? (V2)
perfil_long <- dbGetQuery(con, glue("
  SELECT Variant, {sql_contar_no_nulos(cols_ind)} FROM other_raw GROUP BY Variant")) |>
  pivot_longer(-Variant, names_to = "indicador", values_to = "n_con_dato")

resumen_perfil <- perfil_long |>
  left_join(var_tab |> select(Variant, filas), by = "Variant") |>
  group_by(Variant) |>
  summarise(n_indicadores_con_datos = sum(n_con_dato > 0),
            n_indicadores_completos = sum(n_con_dato == filas),
            .groups = "drop")
ver(resumen_perfil)

cat("\nIndicadores con datos en 'Lower 80 PI':\n  ",
    paste(perfil_long$indicador[perfil_long$Variant == "Lower 80 PI" &
                                  perfil_long$n_con_dato > 0], collapse = ", "), "\n")
cat("\nIndicadores con datos en 'Mean':\n  ",
    paste(perfil_long$indicador[perfil_long$Variant == "Mean" &
                                  perfil_long$n_con_dato > 0], collapse = ", "), "\n")

# 10.3 ¿Qué trae el año 2101 en OtherVariants? (V4)
anio_2101_other <- dbGetQuery(con, "
  SELECT Variant,
         SUM(CASE WHEN TPopulation1Jan  IS NOT NULL THEN 1 ELSE 0 END) AS con_pob_1ene,
         SUM(CASE WHEN TPopulation1July IS NOT NULL THEN 1 ELSE 0 END) AS con_pob_1jul,
         SUM(CASE WHEN TFR              IS NOT NULL THEN 1 ELSE 0 END) AS con_tfr
  FROM other_raw WHERE Time = 2101 GROUP BY Variant ORDER BY Variant")
cat("\nAño 2101 en OtherVariants:\n"); ver(anio_2101_other)

# 10.4 ¿'Mean' coincide con Medium? (V5) -- solo países, años comparables
cmp_mean <- dbGetQuery(con, glue("
  SELECT COUNT(*) AS n_comparadas,
         MAX(ABS(o.TPopulation1July - m.TPopulation1July) /
             NULLIF(m.TPopulation1July, 0)) AS dif_rel_max_pob,
         MAX(ABS(o.TFR - m.TFR)) AS dif_abs_max_tfr
  FROM other_raw o JOIN medium_paises m ON o.LocID = m.LocID AND o.Time = m.Time
  WHERE o.Variant = 'Mean' AND m.Time <= {CFG$ultimo_anio_analisis}"))
cat("\nComparación 'Mean' vs 'Medium' (países):\n"); ver(cmp_mean)

write.csv(var_tab,         file.path(CFG$dir_tablas, "00_other_variants_cobertura.csv"), row.names = FALSE)
write.csv(resumen_perfil,  file.path(CFG$dir_tablas, "00_other_variants_perfil.csv"),    row.names = FALSE)


# ---- 11. Exploración descriptiva y gráficos de control -----------------------
seccion("11. EXPLORACIÓN DESCRIPTIVA Y GRÁFICOS")

# 11.1 Instantánea del último año estimado (medianas SIN ponderar por población)
resumen_2023 <- dbGetQuery(con, glue("
  SELECT COUNT(*)                        AS n_paises,
         ROUND(MEDIAN(TFR), 2)           AS tfr_mediana,
         ROUND(MEDIAN(LEx), 1)           AS lex_mediana,
         ROUND(MEDIAN(MedianAgePop), 1)  AS edad_mediana_de_medianas,
         ROUND(SUM(TPopulation1July) / 1e6, 2) AS poblacion_mundial_mil_millones
  FROM wpp_paises WHERE Time = {CFG$ultimo_anio_estimado}"))
ver(resumen_2023)

# 11.2 Series globales (agregadas en SQL: a R llegan ~151 filas)
serie_global <- dbGetQuery(con, "
  SELECT Time,
         SUM(TPopulation1July) / 1e6 AS pob_miles_millones,
         SUM(Births)                 AS nacimientos_miles,
         SUM(Deaths)                 AS muertes_miles,
         SUM(NetMigrations)          AS migracion_neta_miles
  FROM wpp_paises GROUP BY Time ORDER BY Time") |>
  mutate(tipo_dato = if_else(Time <= CFG$ultimo_anio_estimado, "Estimación", "Proyección"))

mundo_ref <- dbGetQuery(con, glue("
  SELECT Time, TPopulation1July / 1e6 AS pob
  FROM medium_agregados WHERE Location = 'World' AND Time <= {CFG$ultimo_anio_analisis}"))

# 11.3 Verificación visual de la paleta
p0 <- previsualizar_paleta()
print(p0)
guardar_fig(p0, "00_paleta_okabe_ito", ancho = 9, alto = 3)

# 11.4 Gráfico de control 1: población mundial (suma de países vs. fila 'World')
pico <- serie_global |> slice_max(pob_miles_millones, n = 1, with_ties = FALSE)

p1 <- ggplot(serie_global, aes(Time, pob_miles_millones)) +
  capa_proyeccion() +
  geom_area(fill = PAL$estimacion, alpha = 0.08) +
  geom_line(aes(colour = tipo_dato, group = 1), linewidth = 1.25, lineend = "round") +
  geom_point(data = filter(mundo_ref, Time %% 10 == 0), aes(y = pob),
             shape = 21, size = 2.8, stroke = 1.1,
             fill = PAL$fondo, colour = PAL$acento) +
  annotate("point", x = pico$Time, y = pico$pob_miles_millones,
           size = 3.4, colour = PAL$acento) +
  annotate("text", x = pico$Time, y = pico$pob_miles_millones, vjust = -1.1,
           fontface = "bold", size = 3.6, colour = PAL$acento,
           label = paste0("Máximo: ",
                          format(round(pico$pob_miles_millones, 2), decimal.mark = CFG$sep_decimal),
                          " mil M (", pico$Time, ")")) +
  scale_colour_manual(values = c("Estimación" = PAL$estimacion,
                                 "Proyección" = PAL$proyeccion), name = NULL) +
  scale_x_continuous(breaks = seq(1950, 2100, 25), expand = expansion(mult = c(0.01, 0.02))) +
  scale_y_continuous(labels = fmt_miles_millones, limits = c(0, NA),
                     expand = expansion(mult = c(0, 0.14))) +
  labs(title = "Población mundial, 1950-2100",
       subtitle = paste0("Línea: suma de los ", n_paises, " países y áreas (1 de julio). ",
                         "Círculos: fila 'World' de la ONU, cada 10 años.\n",
                         "Si los círculos caen sobre la línea, no hay doble conteo."),
       x = NULL, y = "Población (miles de millones)",
       caption = "Fuente: UN World Population Prospects 2024, variante Medium.") +
  theme_dataquest() +
  guides(colour = "none")
print(p1)
guardar_fig(p1, "00_control_poblacion_mundial", ancho = 9.5, alto = 5.6)

# 11.5 Gráfico de control 2: dispersión de la fecundidad entre países
tfr_bandas <- dbGetQuery(con, "
  SELECT Time,
         quantile_cont(TFR, 0.10) AS p10, quantile_cont(TFR, 0.25) AS p25,
         median(TFR)              AS p50,
         quantile_cont(TFR, 0.75) AS p75, quantile_cont(TFR, 0.90) AS p90
  FROM wpp_paises GROUP BY Time ORDER BY Time")

etq_reemplazo <- paste0("Nivel de reemplazo (",
                        format(CFG$tfr_reemplazo, decimal.mark = CFG$sep_decimal), ")")

p2 <- ggplot(tfr_bandas, aes(Time)) +
  capa_proyeccion() +
  geom_ribbon(aes(ymin = p10, ymax = p90), fill = PAL$estimacion, alpha = 0.14) +
  geom_ribbon(aes(ymin = p25, ymax = p75), fill = PAL$estimacion, alpha = 0.26) +
  geom_hline(yintercept = CFG$tfr_reemplazo, linetype = "dotted",
             colour = PAL$acento, linewidth = 0.7) +
  geom_line(aes(y = p50), colour = PAL$estimacion, linewidth = 1.25, lineend = "round") +
  annotate("text", x = CFG$primer_anio + 1, y = CFG$tfr_reemplazo, label = etq_reemplazo,
           hjust = 0, vjust = -0.8, size = 3.5, fontface = "bold", colour = PAL$acento) +
  scale_x_continuous(breaks = seq(1950, 2100, 25), expand = expansion(mult = c(0.01, 0.02))) +
  scale_y_continuous(limits = c(0, NA), expand = expansion(mult = c(0, 0.06)),
                     labels = fmt_num(1)) +
  labs(title = "Fecundidad: cuánto se parecen los países entre sí",
       subtitle = paste0("Línea: mediana entre países. Banda oscura: 25 %-75 % de los países. ",
                         "Banda clara: 10 %-90 %.\n",
                         "Cada país pesa igual, sin ponderar por población."),
       x = NULL, y = "Hijos por mujer (TFR)",
       caption = "Fuente: UN World Population Prospects 2024, variante Medium.") +
  theme_dataquest()
print(p2)
guardar_fig(p2, "00_control_fecundidad_dispersion", ancho = 9.5, alto = 5.6)


# ---- 12. Persistencia --------------------------------------------------------
seccion("12. GUARDADO")

ruta_parquet <- file.path(CFG$dir_clean, CFG$f_parquet)
n_guardadas <- dbExecute(con, glue("COPY (SELECT * FROM wpp_paises)
                                    TO '{ruta_parquet}' (FORMAT PARQUET)"))
verificar(n_guardadas == n_wpp,
          paste0("Parquet guardado con ", format(n_guardadas, big.mark = ","), " filas."),
          "El número de filas guardadas no coincide con la vista maestra.")

saveRDS(notes, file.path(CFG$dir_clean, CFG$f_dicc))

# Resumen de la Fase 0 (insumo para el reporte y la sección de metodología)
resumen_fase0 <- list(
  fecha            = Sys.Date(),
  n_paises         = n_paises,
  n_agregados      = n_agreg,
  filas_maestra    = n_wpp,
  anios            = c(CFG$primer_anio, CFG$ultimo_anio_analisis),
  dif_max_vs_world = dif_max,
  indicadores      = cols_ind,
  doubling_censura = censura,
  births_dif_max   = chk_births$dif_max,
  other_variantes  = var_tab,
  other_perfil     = resumen_perfil,
  instantanea_2023 = resumen_2023
)
saveRDS(resumen_fase0, file.path(CFG$dir_clean, "resumen_fase0.rds"))
writeLines(capture.output(sessionInfo()), file.path(CFG$dir_tablas, "00_sessionInfo.txt"))

cat("\nFase 0 completa. Para continuar en otros scripts:\n",
    "  con <- DBI::dbConnect(duckdb::duckdb())\n",
    "  DBI::dbExecute(con, \"CREATE VIEW wpp AS SELECT * FROM read_parquet('",
    ruta_parquet, "')\")\n", sep = "")

# dbDisconnect(con, shutdown = TRUE)   # ejecutar al terminar la sesión