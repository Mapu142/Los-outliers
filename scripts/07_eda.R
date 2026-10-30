# ==============================================================================
# ASA DataQuest 2026 - WPP2024
# Script 07: Análisis exploratorio (Fase 2, pasos 7 a 10 del plan)
# ------------------------------------------------------------------------------
# Responde, de forma EXPLORATORIA (sin pruebas de hipótesis; plan §7):
#   1. Tendencias por región y mundo, con el quiebre estimación/proyección (Paso 7).
#   2. Transición demográfica: TFR frente a esperanza de vida, y reemplazo (Paso 8).
#   3. Correlaciones entre indicadores no redundantes: evidencia para cerrar D10 (Paso 9).
#   4. Quiebres históricos: caídas anómalas de la esperanza de vida y picos de
#      migración neta, con foco en Colombia (Paso 10).
#   5. Colombia frente a América Latina y el mundo (pregunta central del plan).
#
# Convenciones: países = ISO3 no nulo (D1); universo >= 1 millón en 2023 (D12);
# peso igual por país (D9); agregados de la ONU solo como referencia (D5).
#
# Entradas : data/clean/wpp_paises_medium_suppl.parquet ; Medium crudo (solo agregados)
# Salidas  : output/figuras/07_*.png ; output/tablas/07_*.csv ; output/tablas/07_resumen_eda.md
# Ejecutar de arriba hacia abajo, desde la raíz del proyecto.
# ==============================================================================

# ---- 0. Entorno --------------------------------------------------------------
if (!file.exists("R/config.R")) stop("Abre el proyecto (.Rproj) o fija setwd() en la raíz.")
paquetes <- c("DBI", "duckdb", "dplyr", "tidyr", "glue", "tibble", "ggplot2", "scales")
faltan <- setdiff(paquetes, rownames(installed.packages()))
if (length(faltan) > 0) install.packages(faltan)
invisible(lapply(paquetes, library, character.only = TRUE))
source("R/config.R",         encoding = "UTF-8")
source("R/utils_datos.R",    encoding = "UTF-8")
source("R/tema.R",           encoding = "UTF-8")
source("R/utils_espacial.R", encoding = "UTF-8")   # solo se usa md_tabla()
crear_directorios()
set.seed(CFG$semilla)

# Parámetros declarados ANTES de mirar los resultados (plan §7)
UMBRAL_CAIDA_LEX  <- -1      # años de esperanza de vida perdidos en un solo año
UMBRAL_CAIDA_FUER <- -2
UMBRAL_REDUND     <- 0.90    # |rho de Spearman| desde el cual dos indicadores se consideran redundantes
ANIOS_CORR        <- c(2023L, 2050L)
ANIOS_TRANS       <- c(1950L, 1980L, 2023L, 2100L)
EDADES_REF        <- c(40, 50)

REGIONES <- c("Africa", "Asia", "Europe", "Latin America and the Caribbean", "Northern America", "Oceania")
NOMBRES_ES <- c("Africa" = "África", "Asia" = "Asia", "Europe" = "Europa",
                "Latin America and the Caribbean" = "América Latina y el Caribe",
                "Northern America" = "América del Norte", "Oceania" = "Oceanía", "World" = "Mundo")
COL_REG <- c(PAL$region, "World" = "#333333")
CAP_WPP <- "Fuente: UN World Population Prospects 2024, variante Medium."

primer_anio <- function(t, cond) {
  i <- which(cond)[1]
  if (is.na(i)) NA_integer_ else as.integer(t[i])
}

con <- conectar_duckdb(if (exists("con")) con else NULL)
dbExecute(con, glue("CREATE OR REPLACE VIEW wpp AS
                     SELECT * FROM read_parquet('{file.path(CFG$dir_clean, CFG$f_parquet)}')"))
crear_vista_csv(con, "medium_raw", CFG$f_medium)


# ---- 1. Datos ----------------------------------------------------------------
seccion("1. DATOS")

# 1.1 Agregados de la ONU (solo referencia, D5): seis regiones geográficas y el mundo
lista_sql <- paste(sprintf("'%s'", c(REGIONES, "World")), collapse = ", ")
agreg <- dbGetQuery(con, glue("
  SELECT LocID, Location, Time, TFR AS tfr, LEx AS lex, MedianAgePop AS edad_mediana,
         TPopulation1July AS pob_miles
  FROM medium_raw
  WHERE NOT ({SQL_ES_PAIS}) AND Location IN ({lista_sql}) AND Time <= {CFG$ultimo_anio_analisis}")) |>
  group_by(Location, Time) |> slice_min(LocID, n = 1, with_ties = FALSE) |> ungroup()
n_esp <- 7 * (CFG$ultimo_anio_analisis - CFG$primer_anio + 1)
verificar(nrow(agreg) == n_esp,
          paste0("Agregados de referencia: 6 regiones + Mundo, ", nrow(agreg), " filas."),
          paste0("Agregados: ", nrow(agreg), " filas; se esperaban ", n_esp,
                 ". Revisar los nombres de las regiones en el archivo Medium."), fatal = FALSE)

# 1.2 Región de cada país: se sube por ParentID hasta una de las seis regiones
jerarquia <- dbGetQuery(con, "SELECT DISTINCT LocID, Location, ParentID FROM medium_raw")
region_de <- function(loc_id) {
  actual <- loc_id
  for (i in 1:6) {
    fila <- match(actual, jerarquia$LocID)
    if (is.na(fila)) return(NA_character_)
    padre <- jerarquia$ParentID[fila]
    if (is.na(padre)) return(NA_character_)
    nom <- jerarquia$Location[match(padre, jerarquia$LocID)]
    if (!is.na(nom) && nom %in% REGIONES) return(nom)
    actual <- padre
  }
  NA_character_
}
paises_ref <- dbGetQuery(con, "SELECT DISTINCT LocID, ISO3_code AS iso3, Location FROM wpp")
regiones_pais <- paises_ref |> mutate(region = vapply(LocID, region_de, character(1)))
# Respaldo (D30): la jerarquía de ParentID no resolvió estos 5 países, que forman la región
# "Northern America" en la clasificación geográfica de la ONU. Solo se rellenan los NA.
REGION_MANUAL <- c(CAN = "Northern America", USA = "Northern America", BMU = "Northern America",
                   SPM = "Northern America", GRL = "Northern America")
sin_reg <- is.na(regiones_pais$region) & regiones_pais$iso3 %in% names(REGION_MANUAL)
regiones_pais$region[sin_reg] <- unname(REGION_MANUAL[regiones_pais$iso3[sin_reg]])
cat("Regiones asignadas manualmente (respaldo):", sum(sin_reg), "países\n")
verificar(!anyNA(regiones_pais$region),
          "Los 237 países tienen región geográfica asignada.",
          paste0("Países sin región: ", paste(regiones_pais$iso3[is.na(regiones_pais$region)], collapse = ", "),
                 " (aparecerán en gris)."), fatal = FALSE)

# 1.3 Panel país-año
panel <- dbGetQuery(con, "
  SELECT LocID, ISO3_code AS iso3, Location, Time, tipo_dato,
         TFR AS tfr, NRR AS nrr, LEx AS lex, LE60 AS le60, MedianAgePop AS edad_mediana,
         CBR AS cbr, CDR AS cdr, IMR AS imr, Q5 AS q5, NatChangeRT AS nat_rt, CNMR AS cnmr,
         PopGrowthRate AS crec, Births AS births, Deaths AS deaths,
         NetMigrations AS migr_neta, TPopulation1July AS pob_miles
  FROM wpp") |>
  left_join(regiones_pais |> select(iso3, region), by = "iso3")

universo <- panel |> filter(Time == CFG$ultimo_anio_estimado, pob_miles >= CFG$umbral_universo_miles) |> pull(iso3)
panel_u <- panel |> filter(iso3 %in% universo) |> arrange(iso3, Time) |>
  group_by(iso3) |>
  mutate(gan10 = edad_mediana - lag(edad_mediana, 10),     # ganancia de edad mediana en 10 años
         indice_vital = log(births / deaths)) |>           # >0: más nacimientos que muertes
  ungroup()
cat("Universo:", length(universo), "países | filas del panel:", nrow(panel_u), "\n")
cat("Países del universo por región:\n")
ver(panel_u |> filter(Time == CFG$ultimo_anio_estimado) |> count(region, name = "paises"))


# ---- 2. Tendencias por región (Paso 7) ---------------------------------------
seccion("2. TENDENCIAS POR REGIÓN")

ETQ_VAR3 <- c("Hijos por mujer (TFR)", "Esperanza de vida al nacer (años)", "Edad mediana (años)")
reg_long <- agreg |>
  pivot_longer(c(tfr, lex, edad_mediana), names_to = "variable", values_to = "valor") |>
  mutate(etiqueta = factor(recode(variable, tfr = ETQ_VAR3[1], lex = ETQ_VAR3[2], edad_mediana = ETQ_VAR3[3]),
                           levels = ETQ_VAR3),
         mundo = Location == "World")
ref_tfr <- tibble(etiqueta = factor(ETQ_VAR3[1], levels = ETQ_VAR3), y = CFG$tfr_reemplazo)

p1 <- ggplot(reg_long, aes(Time, valor, colour = Location, linetype = mundo, linewidth = mundo)) +
  capa_proyeccion(etiquetas = FALSE) +
  geom_hline(data = ref_tfr, aes(yintercept = y), linetype = "dotted", colour = PAL$acento,
             linewidth = 0.5) +
  geom_line(lineend = "round") +
  facet_wrap(~ etiqueta, ncol = 1, scales = "free_y") +
  scale_colour_manual(values = COL_REG, labels = NOMBRES_ES, name = NULL) +
  scale_linetype_manual(values = c("FALSE" = "solid", "TRUE" = "dashed"), guide = "none") +
  scale_linewidth_manual(values = c("FALSE" = 1, "TRUE" = 1.1), guide = "none") +
  scale_x_continuous(breaks = seq(1950, 2100, 25), expand = expansion(mult = c(0.01, 0.02))) +
  scale_y_continuous(labels = fmt_num(0.1)) +
  guides(colour = guide_legend(nrow = 2, byrow = TRUE)) +
  labs(title = "La fecundidad converge entre regiones; la edad mediana, no",
       subtitle = paste0("Valores de las regiones geográficas de la ONU (referencia). Línea punteada naranja: ",
                         "reemplazo (2,1 hijos por mujer).\nZona sombreada: proyección (variante Medium)."),
       x = NULL, y = NULL, caption = CAP_WPP) +
  theme_dataquest()
print(p1); guardar_fig(p1, "07_tendencias_regionales", ancho = 9.5, alto = 10)

anio_ref <- c(1950, 1975, 2000, 2023, 2050, 2075, 2100)
tab_reg <- agreg |> filter(Time %in% anio_ref) |>
  mutate(region = NOMBRES_ES[Location]) |>
  select(region, Time, tfr, lex, edad_mediana) |>
  mutate(across(c(tfr, lex, edad_mediana), ~ round(.x, 1)))
write.csv(tab_reg, file.path(CFG$dir_tablas, "07_tendencias_regionales.csv"), row.names = FALSE)
cat("Edad mediana por región (años clave):\n")
ver(tab_reg |> select(region, Time, edad_mediana) |> pivot_wider(names_from = Time, values_from = edad_mediana))


# ---- 3. Transición demográfica (Paso 8) --------------------------------------
seccion("3. TRANSICIÓN DEMOGRÁFICA: TFR FRENTE A ESPERANZA DE VIDA")

niv_tr <- sprintf("%d · %s", ANIOS_TRANS, if_else(ANIOS_TRANS <= CFG$ultimo_anio_estimado, "estimación", "proyección"))
tr_df <- panel_u |> filter(Time %in% ANIOS_TRANS) |>
  mutate(panel = factor(sprintf("%d · %s", Time, if_else(Time <= CFG$ultimo_anio_estimado, "estimación", "proyección")),
                        levels = niv_tr))
col_tr <- tr_df |> filter(iso3 == "COL")

p2 <- ggplot(tr_df, aes(tfr, lex)) +
  geom_vline(xintercept = CFG$tfr_reemplazo, linetype = "dotted", colour = PAL$acento, linewidth = 0.5) +
  geom_point(aes(size = pob_miles, colour = region), alpha = 0.7) +
  geom_point(data = col_tr, aes(size = pob_miles), shape = 21, fill = NA, colour = "black", stroke = 1.3) +
  geom_text(data = col_tr, label = "Colombia", nudge_y = 3.2, size = 3.3, fontface = "bold") +
  facet_wrap(~ panel, ncol = 2) +
  scale_size_area(max_size = 13, guide = "none") +
  scale_colour_manual(values = PAL$region, labels = NOMBRES_ES, name = NULL, na.value = "grey60") +
  scale_x_continuous(labels = fmt_num(0.1)) +
  guides(colour = guide_legend(nrow = 2, byrow = TRUE, override.aes = list(size = 3.5))) +
  labs(title = "Transición demográfica: fecundidad frente a esperanza de vida",
       subtitle = "Cada burbuja es un país; su tamaño es la población. Línea punteada: reemplazo (2,1 hijos por mujer).",
       x = "Hijos por mujer (TFR)", y = "Esperanza de vida al nacer (años)",
       caption = paste0(CAP_WPP, " ", length(universo), " países con >= 1 millón de habitantes.")) +
  theme_dataquest(rejilla = "xy")
print(p2); guardar_fig(p2, "07_transicion_tfr_esperanza_vida", ancho = 10, alto = 8)


# ---- 4. Reemplazo generacional (Paso 8) --------------------------------------
seccion("4. NIVEL DE REEMPLAZO")

reemp <- panel_u |> group_by(Time) |>
  summarise(pct_paises = 100 * mean(tfr < CFG$tfr_reemplazo),
            pct_pob = 100 * sum(pob_miles[tfr < CFG$tfr_reemplazo]) / sum(pob_miles),
            pct_paises_nrr = 100 * mean(nrr < 1), .groups = "drop")
reemp_clave <- reemp |> filter(Time %in% anio_ref) |> mutate(across(-Time, ~ round(.x, 1)))
ver(reemp_clave)
anio_mitad_paises <- primer_anio(reemp$Time, reemp$pct_paises >= 50)
anio_mitad_pob    <- primer_anio(reemp$Time, reemp$pct_pob >= 50)
col_reemp <- primer_anio(panel_u$Time[panel_u$iso3 == "COL"],
                         panel_u$tfr[panel_u$iso3 == "COL"] < CFG$tfr_reemplazo)
cat(sprintf("\nPrimer año con >= 50 %% de los países bajo el reemplazo (TFR): %s\n", anio_mitad_paises))
cat(sprintf("Primer año con >= 50 %% de la población viviendo bajo el reemplazo: %s\n", anio_mitad_pob))
cat(sprintf("Colombia baja del reemplazo (TFR < 2,1) en: %s\n", col_reemp))
write.csv(reemp, file.path(CFG$dir_tablas, "07_reemplazo.csv"), row.names = FALSE)

# Los saltos de la serie de población (hacia 1990 y 2020) deberían corresponder a países muy
# grandes que cruzan el reemplazo ese año: se comprueba en lugar de suponerlo.
cruce_reemp <- panel_u |> group_by(iso3, Location) |>
  summarise(pob_2023 = pob_miles[Time == CFG$ultimo_anio_estimado],
            anio_bajo_reemplazo = primer_anio(Time, tfr < CFG$tfr_reemplazo), .groups = "drop") |>
  arrange(desc(pob_2023)) |> head(12) |>
  mutate(pob_2023 = round(pob_2023))
cat("\nAño en que los 12 países más poblados bajan del reemplazo (TFR < 2,1):\n")
ver(cruce_reemp)
write.csv(cruce_reemp, file.path(CFG$dir_tablas, "07_reemplazo_paises_grandes.csv"), row.names = FALSE)

NOM_REEMP <- c("pct_paises" = "Países con TFR < 2,1", "pct_pob" = "Población que vive en países con TFR < 2,1",
               "pct_paises_nrr" = "Países con NRR < 1")
reemp_long <- reemp |> pivot_longer(-Time, names_to = "serie", values_to = "pct") |>
  mutate(serie = factor(NOM_REEMP[serie], levels = unname(NOM_REEMP)))
p3 <- ggplot(reemp_long, aes(Time, pct, colour = serie)) +
  capa_proyeccion(etiquetas = FALSE) +
  geom_hline(yintercept = 50, linetype = "dotted", colour = PAL$texto_suave, linewidth = 0.4) +
  geom_line(linewidth = 1.2, lineend = "round") +
  scale_colour_manual(values = setNames(c(PAL$estimacion, PAL$acento, PAL$okabe_ito[["verde"]]), unname(NOM_REEMP)),
                      name = NULL) +
  scale_x_continuous(breaks = seq(1950, 2100, 25), expand = expansion(mult = c(0.01, 0.02))) +
  scale_y_continuous(limits = c(0, 100), labels = fmt_num(1, " %"), expand = expansion(mult = c(0, 0.04))) +
  labs(title = "Países y población bajo el nivel de reemplazo",
       subtitle = paste0("La mitad de los países baja del reemplazo en ", anio_mitad_paises,
                         "; la mitad de la población, en ", anio_mitad_pob, ". Colombia baja en ", col_reemp, ".\n",
                         "NRR < 1: cada generación de mujeres no se reemplaza a sí misma (incluye mortalidad)."),
       x = NULL, y = "Porcentaje", caption = paste0(CAP_WPP, " ", length(universo), " países; peso igual por país salvo la serie de población.")) +
  theme_dataquest()
print(p3); guardar_fig(p3, "07_reemplazo_generacional", ancho = 9.5, alto = 5.8)


# ---- 5. Correlaciones y redundancia (Paso 9; evidencia para D10) --------------
seccion("5. CORRELACIONES (SPEARMAN) Y REDUNDANCIA")

VARS_COR <- c("tfr", "nrr", "lex", "le60", "edad_mediana", "cbr", "cdr", "imr", "q5",
              "nat_rt", "cnmr", "crec", "indice_vital", "gan10")
ETQ_COR <- c(tfr = "TFR", nrr = "NRR", lex = "Esp. de vida al nacer", le60 = "Esp. de vida a los 60",
             edad_mediana = "Edad mediana", cbr = "Tasa de natalidad", cdr = "Tasa de mortalidad",
             imr = "Mortalidad infantil", q5 = "Mortalidad < 5 años", nat_rt = "Crecimiento natural",
             cnmr = "Migración neta (tasa)", crec = "Crecimiento poblacional",
             indice_vital = "Índice vital (log)", gan10 = "Ganancia de edad mediana (10 a)")

matriz_cor <- function(anio) {
  X <- panel_u |> filter(Time == anio) |> select(all_of(VARS_COR))
  cor(X, method = "spearman", use = "pairwise.complete.obs")
}
pares_redund <- function(R, umbral) {
  idx <- which(upper.tri(R) & abs(R) >= umbral, arr.ind = TRUE)
  tibble(a = rownames(R)[idx[, 1]], b = colnames(R)[idx[, 2]], rho = round(R[idx], 3)) |>
    arrange(desc(abs(rho)))
}
R_lista <- lapply(setNames(ANIOS_CORR, ANIOS_CORR), matriz_cor)
# OJO: dentro de mutate(), `a` es la columna de pares_redund(), no el argumento; por eso `anio` salía NA.
pares_all <- bind_rows(lapply(names(R_lista), function(an) {
  pares_redund(R_lista[[an]], UMBRAL_REDUND) |> mutate(anio = as.integer(an))
}))
cat("Pares con |rho| >= ", UMBRAL_REDUND, " (candidatos a redundancia):\n", sep = "")
ver(pares_all |> mutate(a = ETQ_COR[a], b = ETQ_COR[b]))
write.csv(pares_all, file.path(CFG$dir_tablas, "07_pares_redundantes.csv"), row.names = FALSE)
write.csv(as.data.frame(R_lista[["2023"]]) |> tibble::rownames_to_column("indicador"),
          file.path(CFG$dir_tablas, "07_correlaciones_2023.csv"), row.names = FALSE)

R23 <- R_lista[["2023"]]
ord <- hclust(as.dist(1 - abs(R23)), method = "average")$order
nom <- rownames(R23)[ord]
Rl <- as.data.frame(as.table(R23[nom, nom]))
names(Rl) <- c("v1", "v2", "rho")
Rl$v1 <- factor(Rl$v1, levels = nom); Rl$v2 <- factor(Rl$v2, levels = rev(nom))
p4 <- ggplot(Rl, aes(v1, v2, fill = rho)) +
  geom_tile(colour = PAL$fondo, linewidth = 0.6) +
  geom_text(aes(label = format(round(rho, 2), nsmall = 2, decimal.mark = CFG$sep_decimal)),
            size = 2.5, colour = PAL$texto) +
  scale_fill_gradient2(low = PAL$okabe_ito[["bermellon"]], mid = "white", high = PAL$okabe_ito[["azul"]],
                       limits = c(-1, 1), name = "Spearman") +
  scale_x_discrete(labels = function(x) unname(ETQ_COR[x])) +
  scale_y_discrete(labels = function(x) unname(ETQ_COR[x])) +
  labs(title = "Correlación entre indicadores demográficos (2023)",
       subtitle = paste0("Correlación de Spearman entre indicadores, 2023, ", length(universo),
                         " países. Ordenados por similitud: los bloques indican redundancia."),
       x = NULL, y = NULL, caption = CAP_WPP) +
  theme_dataquest(rejilla = "ninguna") +
  theme(axis.text.x = element_text(angle = 45, hjust = 1), legend.position = "right")
print(p4); guardar_fig(p4, "07_correlaciones_2023", ancho = 9.5, alto = 8)

# Grupos de redundancia con enlace promedio: dentro de cada grupo la |rho| MEDIA es >= umbral.
# (La versión anterior, por componentes conexas, encadenaba casi todo en un solo bloque porque
#  basta una pareja con |rho| >= 0.9 para unir dos indicadores.)
grupos_redund <- function(R, umbral) {
  hc <- hclust(as.dist(1 - abs(R)), method = "average")
  split(colnames(R), cutree(hc, h = 1 - umbral))
}
for (an in names(R_lista)) {
  cat("\nGrupos de indicadores redundantes (", an, ", |rho| medio >= ", UMBRAL_REDUND, "):\n", sep = "")
  for (g in grupos_redund(R_lista[[an]], UMBRAL_REDUND)) cat("  -", paste(ETQ_COR[g], collapse = " | "), "\n")
}
# Máxima |rho| de cada indicador con cualquier otro (2023): ayuda a elegir representantes (D10)
cat("\n|rho| máxima de cada indicador con otro (2023):\n")
ver(tibble(indicador = ETQ_COR[colnames(R23)],
           rho_max_abs = round(apply(abs(R23) - diag(2, ncol(R23)), 2, max), 3)) |> arrange(desc(rho_max_abs)))


# ---- 6. Quiebres históricos de la esperanza de vida (Paso 10) -----------------
seccion("6. CAÍDAS DE LA ESPERANZA DE VIDA")

caidas <- panel_u |> arrange(iso3, Time) |> group_by(iso3) |>
  mutate(d_lex = lex - lag(lex)) |> ungroup() |>
  filter(Time <= CFG$ultimo_anio_estimado, !is.na(d_lex))
n_caidas <- caidas |> group_by(Time) |>
  summarise(n_leve = sum(d_lex <= UMBRAL_CAIDA_LEX), n_fuerte = sum(d_lex <= UMBRAL_CAIDA_FUER), .groups = "drop")
cat(sprintf("Umbrales declarados: caída <= %g año y <= %g años de esperanza de vida en un año.\n",
            UMBRAL_CAIDA_LEX, UMBRAL_CAIDA_FUER))
cat("Años con más países en caída:\n")
ver(n_caidas |> arrange(desc(n_leve)) |> head(10))
cat("\nLas 25 caídas más fuertes (país-año, universo):\n")
top_caidas <- caidas |> arrange(d_lex) |> head(25) |>
  transmute(Location, Time, d_lex = round(d_lex, 1), lex = round(lex, 1))
ver(top_caidas)
write.csv(top_caidas, file.path(CFG$dir_tablas, "07_caidas_lex_top.csv"), row.names = FALSE)
write.csv(n_caidas, file.path(CFG$dir_tablas, "07_caidas_lex_por_anio.csv"), row.names = FALSE)
cat("\nColombia (caídas de al menos medio año):\n")
ver(caidas |> filter(iso3 == "COL", d_lex <= -0.5) |> transmute(Time, d_lex = round(d_lex, 2), lex = round(lex, 1)))

p5 <- ggplot(n_caidas, aes(Time)) +
  geom_col(aes(y = n_leve), fill = PAL$okabe_ito[["celeste"]], width = 0.85) +
  geom_col(aes(y = n_fuerte), fill = PAL$acento, width = 0.85) +
  scale_x_continuous(breaks = seq(1950, 2020, 10), expand = expansion(mult = c(0.01, 0.01))) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.08))) +
  labs(title = "Las caídas masivas de la esperanza de vida se concentran en 2020 y 2021",
       subtitle = paste0("Países cuya esperanza de vida cae al menos ", abs(UMBRAL_CAIDA_LEX), " año (azul claro) o ",
                         abs(UMBRAL_CAIDA_FUER), " años (naranja oscuro) en un solo año. Solo estimaciones."),
       x = NULL, y = "Número de países",
       caption = paste0(CAP_WPP, " ", length(universo), " países. Umbrales fijados antes de ver los resultados.")) +
  theme_dataquest()
print(p5); guardar_fig(p5, "07_caidas_esperanza_vida", ancho = 9.5, alto = 5.2)


# ---- 7. Picos de migración neta y Colombia (Paso 10) --------------------------
seccion("7. PICOS DE MIGRACIÓN NETA")

picos <- panel_u |> filter(Time <= CFG$ultimo_anio_estimado) |> arrange(iso3, Time) |>
  group_by(iso3) |>
  mutate(base = as.numeric(stats::runmed(cnmr, k = 11, endrule = "median")),   # mediana móvil de 11 años
         pico = cnmr - base) |>
  ungroup()
cat("Mayores desviaciones de la tasa de migración neta respecto a su mediana móvil de 11 años (por 1 000 hab.):\n")
top_picos <- picos |> arrange(desc(abs(pico))) |> head(20) |>
  transmute(Location, Time, cnmr = round(cnmr, 1), base = round(base, 1), pico = round(pico, 1),
            migr_neta_miles = round(migr_neta, 0))
ver(top_picos)
write.csv(top_picos, file.path(CFG$dir_tablas, "07_picos_migracion_top.csv"), row.names = FALSE)

col_mig <- panel |> filter(iso3 == "COL")
pk_max <- col_mig |> filter(Time <= CFG$ultimo_anio_estimado) |> slice_max(migr_neta, n = 1, with_ties = FALSE)
pk_min <- col_mig |> filter(Time <= CFG$ultimo_anio_estimado) |> slice_min(migr_neta, n = 1, with_ties = FALSE)
cat(sprintf("\nColombia: máximo de migración neta estimada %s miles en %d; mínimo %s miles en %d.\n",
            format(round(pk_max$migr_neta), big.mark = CFG$sep_miles, decimal.mark = CFG$sep_decimal), pk_max$Time,
            format(round(pk_min$migr_neta), big.mark = CFG$sep_miles, decimal.mark = CFG$sep_decimal), pk_min$Time))
cat("Colombia, mayores picos respecto a su tendencia:\n")
ver(picos |> filter(iso3 == "COL") |> arrange(desc(abs(pico))) |> head(5) |>
      transmute(Time, cnmr = round(cnmr, 1), base = round(base, 1), pico = round(pico, 1)))

p6 <- ggplot(col_mig, aes(Time, migr_neta)) +
  capa_proyeccion(etiquetas = FALSE) +
  geom_hline(yintercept = 0, colour = PAL$texto_suave, linewidth = 0.4) +
  geom_line(colour = PAL$estimacion, linewidth = 1.2, lineend = "round") +
  geom_point(data = pk_max, colour = PAL$acento, size = 3) +
  geom_text(data = pk_max, aes(label = paste0("Máximo: ", format(round(migr_neta), big.mark = CFG$sep_miles, decimal.mark = CFG$sep_decimal),
                                              " mil (", Time, ")")),
            colour = PAL$acento, fontface = "bold", size = 3.4, hjust = 1.05, vjust = -0.6) +
  geom_point(data = pk_min, colour = PAL$acento, size = 3) +
  geom_text(data = pk_min, aes(label = paste0("Mínimo: ", format(round(migr_neta), big.mark = CFG$sep_miles, decimal.mark = CFG$sep_decimal),
                                              " mil (", Time, ")")),
            colour = PAL$acento, fontface = "bold", size = 3.4, hjust = -0.05, vjust = 1.6) +
  scale_x_continuous(breaks = seq(1950, 2100, 25), expand = expansion(mult = c(0.01, 0.02))) +
  scale_y_continuous(labels = fmt_num(1)) +
  labs(title = "Colombia: migración neta estimada y proyectada por la ONU",
       subtitle = paste0("Miles de personas por año (positiva = entran más de las que salen). ",
                         "Pico de ", format(round(pk_max$migr_neta)), " mil en ", pk_max$Time, "; la proyección vuelve a ~0."),
       x = NULL, y = "Miles de personas por año", caption = CAP_WPP) +
  theme_dataquest()
print(p6); guardar_fig(p6, "07_colombia_migracion_neta", ancho = 9.5, alto = 5.2)


# ---- 8. Colombia frente a América Latina y el mundo ---------------------------
seccion("8. COLOMBIA FRENTE A AMÉRICA LATINA Y EL MUNDO")

SERIES <- c("Colombia", "América Latina y el Caribe", "Mundo")
col_ser <- panel |> filter(iso3 == "COL") |> transmute(Time, serie = SERIES[1], tfr, lex, edad_mediana)
lac_ser <- agreg |> filter(Location == "Latin America and the Caribbean") |> transmute(Time, serie = SERIES[2], tfr, lex, edad_mediana)
mun_ser <- agreg |> filter(Location == "World") |> transmute(Time, serie = SERIES[3], tfr, lex, edad_mediana)
ctx <- bind_rows(col_ser, lac_ser, mun_ser) |> mutate(serie = factor(serie, levels = SERIES))

ctx_long <- ctx |> pivot_longer(c(edad_mediana, tfr, lex), names_to = "variable", values_to = "valor") |>
  mutate(etiqueta = factor(recode(variable, tfr = ETQ_VAR3[1], lex = ETQ_VAR3[2], edad_mediana = ETQ_VAR3[3]),
                           levels = c(ETQ_VAR3[3], ETQ_VAR3[1], ETQ_VAR3[2])))
gan_edad <- ctx |> filter(Time %in% c(CFG$ultimo_anio_estimado, CFG$ultimo_anio_analisis)) |>
  select(serie, Time, edad_mediana) |> pivot_wider(names_from = Time, values_from = edad_mediana)
gan_txt <- paste0(gan_edad$serie, " +", round(gan_edad[[3]] - gan_edad[[2]], 1), collapse = "; ")
p7 <- ggplot(ctx_long, aes(Time, valor, colour = serie, linewidth = serie, linetype = serie)) +
  capa_proyeccion(etiquetas = FALSE) +
  geom_line(lineend = "round") +
  facet_wrap(~ etiqueta, ncol = 1, scales = "free_y") +
  scale_colour_manual(values = c("Colombia" = PAL$acento, "América Latina y el Caribe" = PAL$okabe_ito[["verde"]],
                                 "Mundo" = "#333333"), name = NULL) +
  scale_linewidth_manual(values = c("Colombia" = 1.5, "América Latina y el Caribe" = 1, "Mundo" = 1), guide = "none") +
  scale_linetype_manual(values = c("Colombia" = "solid", "América Latina y el Caribe" = "solid", "Mundo" = "dashed"),
                        guide = "none") +
  scale_x_continuous(breaks = seq(1950, 2100, 25), expand = expansion(mult = c(0.01, 0.02))) +
  scale_y_continuous(labels = fmt_num(0.1)) +
  labs(title = "Colombia gana más edad mediana que su región y que el mundo",
       subtitle = paste0("Edad mediana 2023 -> 2100: ", gan_txt, " (agregados de la ONU, solo referencia).\n",
                         "Zona sombreada: proyección (variante Medium)."),
       x = NULL, y = NULL, caption = CAP_WPP) +
  theme_dataquest()
print(p7); guardar_fig(p7, "07_colombia_en_contexto", ancho = 9.5, alto = 10)

umbrales_edad <- bind_rows(lapply(EDADES_REF, function(u) {
  ctx |> group_by(serie) |>
    summarise(umbral = u, anio = primer_anio(Time, edad_mediana >= u), .groups = "drop")
})) |> pivot_wider(names_from = serie, values_from = anio) |> mutate(across(everything(), as.numeric))
cat("Primer año en que la edad mediana alcanza el umbral (NA = no lo alcanza antes de 2100):\n")
ver(umbrales_edad)
write.csv(umbrales_edad, file.path(CFG$dir_tablas, "07_colombia_umbrales_edad.csv"), row.names = FALSE)
ctx_clave <- ctx |> filter(Time %in% anio_ref) |>
  transmute(serie, Time, edad_mediana = round(edad_mediana, 1), tfr = round(tfr, 2), lex = round(lex, 1))
ver(ctx_clave |> select(serie, Time, edad_mediana) |> pivot_wider(names_from = Time, values_from = edad_mediana))


# ---- 9. Resumen para el reporte ----------------------------------------------
seccion("9. RESUMEN (output/tablas/07_resumen_eda.md)")

res <- c(
  paste0("### EDA · corrida del ", format(Sys.time(), "%Y-%m-%d %H:%M")), "",
  paste0("- Universo: ", length(universo), " países (>= 1 millón de habitantes en 2023). Todo es exploratorio."), "",
  "**Reemplazo generacional** (% de países y de población bajo TFR 2,1):", "",
  md_tabla(reemp_clave, 1), "",
  paste0("- La mitad de los países baja del reemplazo en ", anio_mitad_paises, "; la mitad de la población, en ",
         anio_mitad_pob, "; Colombia, en ", col_reemp, "."), "",
  "**Colombia, América Latina y el mundo** (edad mediana):", "",
  md_tabla(ctx_clave |> select(serie, Time, edad_mediana) |> pivot_wider(names_from = Time, values_from = edad_mediana), 1), "",
  "**Primer año en que la edad mediana alcanza el umbral:**", "",
  md_tabla(umbrales_edad), "",
  paste0("**Pares de indicadores con |rho de Spearman| >= ", UMBRAL_REDUND, "** (evidencia para D10):"), "",
  md_tabla(pares_all |> mutate(a = ETQ_COR[a], b = ETQ_COR[b]), 3), "",
  paste0("**Años con más países en caída de la esperanza de vida** (>= ", abs(UMBRAL_CAIDA_LEX), " año):"), "",
  md_tabla(n_caidas |> arrange(desc(n_leve)) |> head(8)), "",
  "**Mayores caídas de la esperanza de vida (país-año):**", "",
  md_tabla(top_caidas |> head(15), 1), "",
  "**Mayores picos de migración neta (tasa por 1 000 hab. respecto a su mediana móvil):**", "",
  md_tabla(top_picos |> head(12), 1), "",
  sprintf("- Colombia: máximo de migración neta estimada %d (miles) en %d; mínimo %d en %d.",
          as.integer(round(pk_max$migr_neta)), pk_max$Time, as.integer(round(pk_min$migr_neta)), pk_min$Time), "")
f_md <- file.path(CFG$dir_tablas, "07_resumen_eda.md")
writeLines(enc2utf8(res), f_md, useBytes = TRUE)
cat("Resumen guardado en:", f_md, "\n", sep = "")

cat("\nCierre del Paso 9 (D10): revisa 07_pares_redundantes.csv y la lista de grupos redundantes de la\n",
    "sección 5. De cada grupo se conserva UN indicador (el más interpretable) para el PCA. D10 se cierra\n",
    "cuando el equipo confirma esa lista.\n", sep = "")
cat("\nLímites: universo de ", length(universo), " países; los agregados regionales son de la ONU y solo sirven\n",
    "de referencia (D5); las proyecciones (2024-2100) son escenarios, no observaciones (D2);\n",
    "los umbrales de caída y de redundancia son ad hoc y se declararon antes de ver los resultados.\n", sep = "")

# dbDisconnect(con, shutdown = TRUE)