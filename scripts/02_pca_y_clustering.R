# ==============================================================================
# R/02_pca_y_clustering.R
# Proyecto: Trayectorias Fisiológicas del Futuro Global · DataQuest 2026
# Fase 2: PCA Longitudinal, Justificación de K, Clustering Semántico y Transición
# ==============================================================================

# ---- 0. Carga de Entorno y Dependencias --------------------------------------
if (!file.exists("R/config.R")) stop("Fije setwd() en la raíz del proyecto.")

library(tidyverse)
library(arrow)
library(FactoMineR)
library(factoextra)
library(cluster)
library(countrycode)

source("R/config.R",      encoding = "UTF-8")
source("R/utils_datos.R", encoding = "UTF-8")
source("R/tema.R",        encoding = "UTF-8")

seccion("FASE 2: INGENIERÍA DE VARIABLES (141 AÑOS) Y BALANCEO")

df_wpp <- arrow::read_parquet(file.path(CFG$dir_clean, CFG$f_parquet))

# 1. Definición de Universo Balanceado basado en el año de corte 2023
paises_universo <- df_wpp %>%
  filter(Time == CFG$ultimo_anio_estimado & TPopulation1July >= CFG$umbral_universo_miles) %>%
  filter(!is.na(ISO3_code) & trimws(ISO3_code) != "") %>%
  pull(ISO3_code)

# 2. Construcción de la matriz con corrección logarítmica y temporal (1960-2100)
df_panel_completo <- df_wpp %>%
  filter(ISO3_code %in% paises_universo & Time <= CFG$ultimo_anio_analisis) %>%
  arrange(ISO3_code, Time) %>%
  group_by(ISO3_code) %>%
  mutate(
    log_IRG = log(Births / na_if(Deaths, 0)),
    Velocidad_Envejecimiento = MedianAgePop - lag(MedianAgePop, 10)
  ) %>%
  ungroup() %>%
  filter(Time >= 1960) %>% # Horizonte corregido a 141 años debido al rezago de 10 años
  select(ISO3_code, Time, Location, TFR, CBR, LEx, LE60, MedianAgePop, log_IRG, Velocidad_Envejecimiento) %>%
  drop_na()

# 3. Verificación estricta de balanceo
conteo_temporal <- df_panel_completo %>% group_by(ISO3_code) %>% summarise(n_anios = n())
panel_balanceado <- length(unique(conteo_temporal$n_anios)) == 1

verificar(
  condicion = panel_balanceado,
  ok = sprintf("Panel balanceado: %d países con %d años (Horizonte de 141 años).", 
               nrow(conteo_temporal), unique(conteo_temporal$n_anios)),
  error = "Desbalance en la estructura matricial.",
  fatal = TRUE
)

seccion("FASE 2: MODELO PCA LONGITUDINAL ANCLADO HISTÓRICAMENTE")

# ---- 4. Ejecución y Control de Signo del PCA ---------------------------------
id_datos   <- df_panel_completo[, c("ISO3_code", "Time", "Location")]
matriz_num <- df_panel_completo[, c("TFR", "CBR", "LEx", "LE60", "MedianAgePop", "log_IRG", "Velocidad_Envejecimiento")]

res_pca <- PCA(matriz_num, scale.unit = TRUE, ncp = 3, graph = FALSE)

# Orientación del signo: Asegurar que valores altos en PC1 simbolicen mayor Madurez
signo_pc1 <- sign(cor(res_pca$ind$coord[,1], df_panel_completo$MedianAgePop))
pc1_corregida <- res_pca$ind$coord[,1] * signo_pc1
pc2_corregida <- res_pca$ind$coord[,2] # Evaluaremos cargas en tabla de salida
pc3_corregida <- res_pca$ind$coord[,3]

df_espacio_factorial <- cbind(id_datos, data.frame(
  PC1_Madurez    = pc1_corregida, 
  PC2_Dinamica   = pc2_corregida, 
  PC3_Estructura = pc3_corregida
))

# Exportación de Auditoría de Cargas y Autovalores
autovalores <- as.data.frame(get_eigenvalue(res_pca)) %>% 
  rownames_to_column(var = "Dimension")
write.csv(autovalores, file.path(CFG$dir_tablas, "02_pca_autovalores.csv"), row.names = FALSE)
variables_calidad <- data.frame(
  Variable    = rownames(res_pca$var$coord),
  PC1_load    = res_pca$var$coord[,1] * signo_pc1,
  PC2_load    = res_pca$var$coord[,2],
  PC3_load    = res_pca$var$coord[,3],
  PC1_cos2    = res_pca$var$cos2[,1],
  PC2_cos2    = res_pca$var$cos2[,2],
  PC3_cos2    = res_pca$var$cos2[,3],
  PC1_contrib = res_pca$var$contrib[,1],
  PC2_contrib = res_pca$var$contrib[,2],
  PC3_contrib = res_pca$var$contrib[,3]
)
write.csv(variables_calidad, file.path(CFG$dir_tablas, "02_pca_calidad_variables.csv"), row.names = FALSE)

seccion("FASE 2: JUSTIFICACIÓN DE K Y CLUSTERING SEMÁNTICO (2024-2100)")

# ---- 5. Recorte de Proyecciones y Diagnóstico de Optimización ----------------
seccion("FASE 2: RECORTE PROYECTADO Y DIAGNÓSTICO DE OPTIMIZACIÓN (2024-2100)")

df_clustering_prep <- df_espacio_factorial %>% filter(Time >= 2024)
matriz_clustering  <- df_clustering_prep[, c("PC1_Madurez", "PC2_Dinamica", "PC3_Estructura")]

# Gráfico de justificación de K (Método del Codo / Inercia) para el reporte
# p_codo <- fviz_nbclust(matriz_clustering, kmeans, method = "wss") +
#   labs(title = "Optimización de Clústeres (Método del Codo)", 
#        subtitle = "Justificación técnica del número K de arquetipos demográficos",
#        x = "Número de Clústeres K", y = "Suma de Cuadrados Internos (Inercia)") +
#   theme_dataquest(rejilla = "y")
# guardar_fig(p_codo, "02_justificacion_k_codo")

# Diagnóstico de Silueta sobre una muestra indexada
set.seed(CFG$semilla)
muestra <- matriz_clustering[sample(nrow(matriz_clustering), 3000), ]
sil_k <- map_dbl(2:8, function(k) {
  km <- kmeans(muestra, centers = k, nstart = 10)
  mean(silhouette(km$cluster, dist(muestra))[, "sil_width"])
})

tab_siluetas <- tibble(K = 2:8, silueta = round(sil_k, 3))
write.csv(tab_siluetas, file.path(CFG$dir_tablas, "02_metricas_diagnostico_siluetas.csv"), row.names = FALSE)


# ---- 6. K-Means y Reordenamiento Semántico Estable --------------------------
seccion("FASE 2: EJECUCIÓN DE K-MEANS Y ALINEACIÓN DE ARQUETIPOS")

# K-Means Fijo K=4 sustentado como decisión sustantiva (Etapas de la Transición Demográfica)
set.seed(CFG$semilla)
km_inicial <- kmeans(matriz_clustering, centers = 4, nstart = 25)

# Ordenamiento semántico por PC1 Media (Arquetipo_1 = Más Joven, Arquetipo_4 = Más Envejecido)
mapeo_clusters <- data.frame(id_orig = km_inicial$cluster, PC1 = matriz_clustering$PC1_Madurez) %>%
  group_by(id_orig) %>%
  summarise(pc1_m = mean(PC1), .groups = "drop") %>%
  arrange(pc1_m) %>%
  mutate(id_semantico = row_number())

cluster_estable <- mapeo_clusters$id_semantico[match(km_inicial$cluster, mapeo_clusters$id_orig)]

# ---- EXPORTACIÓN 4: Centroides Reordenados Semánticamente ----
centroides_estables <- as.data.frame(km_inicial$centers[mapeo_clusters$id_orig, ])
rownames(centroides_estables) <- paste0("Arquetipo_", 1:4)
write.csv(centroides_estables, file.path(CFG$dir_tablas, "02_cluster_centroides.csv"), row.names = TRUE)

# Inyectar continentes y etiquetas estables definitivas para las proyecciones
df_arquetipos_final <- df_clustering_prep %>%
  mutate(
    Cluster_Arquetipo = factor(cluster_estable, levels = 1:4, labels = paste0("Arquetipo_", 1:4)),
    Continente = countrycode(ISO3_code, "iso3c", "continent", custom_match = c("XKX" = "Europe"))
  )

# Guardar matriz maestra proyectada para la pestaña 3 de la App Shiny (Mapas)
arrow::write_parquet(df_arquetipos_final, file.path(CFG$dir_clean, "wpp_matriz_arquetipos_proyecciones.parquet"))


# ---- 7. Funciones de Transición, Sensibilidad y Recuperación de Históricos ---
seccion("FASE 2: ANÁLISIS DE SENSIBILIDAD Y EXPORTACIONES HISTÓRICAS COMPLETAS")

# Función genérica de transiciones persistentes (Regla de consistencia temporal de 3 años)
transiciones <- function(df, racha = 3) {
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
    select(-run, -largo, -inicio)
}

# Análisis de sensibilidad del hito de Colombia guardado en disco
sens_k <- map_dfr(3:6, function(k) {
  set.seed(CFG$semilla)
  km    <- kmeans(matriz_clustering, centers = k, nstart = 25)
  orden <- order(tapply(matriz_clustering$PC1_Madurez, km$cluster, mean))
  
  df_clustering_prep %>%
    mutate(Cluster_Arquetipo = factor(match(km$cluster, orden))) %>%
    filter(ISO3_code == "COL") %>%
    transiciones(racha = CFG$racha_cruce) %>%
    transmute(K = k, Anio = Time, Hacia = Cluster_Arquetipo)
})
write.csv(sens_k, file.path(CFG$dir_tablas, "02_sensibilidad_hito_colombia.csv"), row.names = FALSE)

# ---- EXPORTACIÓN: Trayectoria de Colombia para la Pestaña 1 ----
df_trayectoria_colombia <- df_arquetipos_final %>% 
  filter(ISO3_code == "COL") %>%
  arrange(Time)
write.csv(df_trayectoria_colombia, file.path(CFG$dir_tablas, "02_trayectoria_transicion_colombia.csv"), row.names = FALSE)

# ---- EXPORTACIÓN: Transiciones persistentes globales de todos los países ----
df_transiciones_globales <- transiciones(df_arquetipos_final, racha = CFG$racha_cruce)
arrow::write_parquet(df_transiciones_globales, file.path(CFG$dir_clean, "wpp_transiciones_persistentes_globales.parquet"))

# ---- EXPORTACIÓN: Coordenadas de todo el periodo (1960-2100) con Continente para el pasado ----
df_espacio_factorial_final <- df_espacio_factorial %>%
  mutate(Continente = countrycode(ISO3_code, "iso3c", "continent", custom_match = c("XKX" = "Europe")))
arrow::write_parquet(df_espacio_factorial_final, file.path(CFG$dir_clean, "wpp_pca_coordenadas_todo_periodo.parquet"))


# ---- 8. Círculo de Correlación de Variables Corregido y Alineado -------------
seccion("FASE 2: CONSTRUCCIÓN DEL CÍRCULO DE CORRELACIÓN DE VARIABLES")

p_circulo <- ggplot(variables_calidad, aes(x = PC1_load, y = PC2_load)) +
  annotate("path", x = cos(seq(0, 2*pi, length.out = 100)), y = sin(seq(0, 2*pi, length.out = 100)),
           color = PAL$texto_suave, linewidth = 0.3, linetype = "dashed") +
  geom_segment(aes(xend = PC1_load, yend = PC2_load, x = 0, y = 0),
               arrow = arrow(length = unit(0.2, "cm")), color = PAL$acento, linewidth = 0.8) +
  ggrepel::geom_text_repel(aes(label = Variable), color = PAL$texto, size = 3.8, fontface = "bold") +
  geom_vline(xintercept = 0, color = PAL$texto_suave, linewidth = 0.2) +
  geom_hline(yintercept = 0, color = PAL$texto_suave, linewidth = 0.2) +
  labs(
    title = "Estructura de la Madurez y Dinámica Demográfica",
    subtitle = "Círculo de correlación construido desde cargas corregidas en signo (1960-2100)",
    x = "Componente Principal 1 (Madurez Estructural)",
    y = "Componente Principal 2 (Dinámica / Velocidad)",
    caption = "Fuente: Cálculos propios. Infraestructura DataQuest 2026. Ejes alineados con coordenadas."
  ) +
  theme_dataquest(rejilla = "xy")

guardar_fig(p_circulo, "02_pca_circulo_variables")

cat("  [OK]    Toda la infraestructura de datos guardada para la App Shiny.\n")
