ASA DataQuest 2026 · UN World Population Prospects 2024 Guía de navegación, registro de hallazgos y plan de trabajo del proyecto. Léela completa antes de escribir código nuevo y actualízala al cerrar cada fase.

Estado actual (31-oct-2026): 🆕 Fase 0 completa. Fase 1 cerrada. Ampliación espacial terminada (corrida D vigente). Fase 2 cerrada (EDA + PCA longitudinal + clustering semántico). 🆕 Fase 3 avanzada: pronósticos propios vs. ONU completados (script 10); integración con bandas PI oficiales y triangulación del punto crítico de Colombia (script 11); app Shiny de series de tiempo lista (app_ts); 🆕 app unificada en progreso con 4 módulos Shiny nuevos. Pendiente: incertidumbre con OtherVariants (Paso 15), cruce de arquetipos con pronósticos, completar pestañas de mapa y validación en la app unificada, y reporte Rmd.

## Objetivo

Construir un análisis ganador del concurso ASA DataQuest 2026 con los datos WPP 2024 de la ONU, entregando:

-   Un reporte R Markdown interactivo (introducción, metodología, hallazgos, recomendaciones).
-   🆕 Una aplicación Shiny unificada (ver §13) que combine: explorador de series, PCA y arquetipos, discrepancias vs. ONU, puntos críticos de soporte, mapa mundial animado, validación de modelos y transiciones demográficas.
-   Un código reproducible y un registro de decisiones, alineados con las *Ethical Guidelines for Statistical Practice* de la ASA (2022).

**Principio rector:** una pregunta central bien respondida vale más que muchos análisis dispersos. El archivo Medium basta para una entrega sólida; OtherVariants es opcional y sirve para la incertidumbre.

## Estado del proyecto

| Fase | Contenido | Estado |
|----|----|----|
| 0 | ETL, validación, parquet limpio, tema visual | ✅ Completa |
| 1 | Pregunta central, plan analítico y datos externos | ✅ Cerrada |
| 1b | Ampliación espacial: geometrías, mapas, Moran y LISA | ✅ Corrida D vigente |
| 2 | EDA + PCA longitudinal + clustering semántico | ✅ Cerrada (07 ✅, 02_PCA ✅) |
| 3 | Modelado, pronósticos propios e incertidumbre | 🆕 ⬜⬛ En progreso (10 ✅, 11 ✅, 15 ⏳) |
| 4 | Reporte Rmd | ⬜ |
| 5 | 🆕 App Shiny unificada | ⬜⬛ Cuatro módulos listos; faltan mapa y validación |
| 6 | Cierre y revisión ética | ⬜ |

### Casillas de la Fase 2 (cerradas):

-   [x] Script 07: EDA completo (tendencias, transición demográfica, correlaciones, quiebres históricos, Colombia en contexto). Cierra D10.
-   [x] Script 02_PCA: PCA longitudinal anclado históricamente (1960-2100), K=4 justificado por silueta, arquetipos reordenados semánticamente (joven → envejecido), transiciones persistentes con racha de 3 años.
-   [x] Módulo Shiny `R/mod_pca_clusters.R` y app independiente `app_pca.R`.

### Casillas de la Fase 3 (actualizadas):

-   [x] Script 10: pronósticos propios (ETS, GAM, estructural) con backtesting en 1990/2000/2010; elección de método por MASE; IC empíricos; punto crítico pensional.
-   [x] Script 11: conciliación de RS (portal vs. PSR65 del script 03), regla D16 (pronóstico propio vs. banda oficial 80%), triangulación del año crítico de Colombia (ONU, DANE, propio).
-   [x] App Shiny de series de tiempo (`app_ts`) con bs4Dash.
-   [ ] Paso 15: perfil de OtherVariants (V2-V5) e incertidumbre cruzada con clusters.
-   [ ] Cruzar arquetipos del PCA con los pronósticos propios.

### Casillas de la Fase 5 (app unificada, actualizadas):

-   [x] `app/unificada/global.R`: carga única de datos con detección de raíz del proyecto.
-   [x] `app/unificada/app_unificada.R`: punto de entrada con 8 pestañas y filtros globales.
-   [x] `mod_series.R`: explorador de series históricas y proyectadas.
-   [x] `mod_pca_clusters.R`: arquetipos, trayectorias y estadios.
-   [x] `mod_discrepancias.R`: discrepancias vs. ONU y regla D16.
-   [x] `mod_criticos.R`: puntos críticos de RS con triangulación DANE/ONU/propio.
-   [ ] `mod_mapa.R`: combinar mapa de `app_ts` con LISA del script 06.
-   [ ] `mod_validacion.R`: migrar la pestaña de validación de `app_ts`.

## Estructura de carpetas

```         
proyecto-wpp2024/
  ├── README.md
  ├── DECISIONES.md
  ├── PLAN_ANALITICO.md
  ├── ANALISIS_ESPACIAL.md
  ├── 🆕 ANALISIS_SERIES_TIEMPO.md        <- bitácora del módulo de pronósticos
  ├── proyecto-wpp2024.Rproj
  │
  ├── data/
  │   ├── raw/
  │   │   ├── WPP2024_Demographic_Indicators_Medium_csv.gz
  │   │   ├── WPP2024_Demographic_Indicators_OtherVariants_csv.gz
  │   │   ├── WPP2024_Demographic_Indicators_notes.csv
  │   │   ├── WPP2024_Supplement_Births_and_LE60.csv
  │   │   └── externos/
  │   │       ├── FUENTES.md
  │   │       ├── WPP2024_PopulationBySingleAgeSex_Medium_*.csv
  │   │       ├── PPED-AreaSexoEdadNac-1950-2017.xlsx
  │   │       ├── PPED-AreaSexoEdadNac-2018-2070.xlsx
  │   │       ├── natural_earth_admin0_50m.gpkg
  │   │       └── documentacion/
  │   └── clean/
  │       ├── wpp_paises_medium_suppl.parquet
  │       ├── diccionario_indicadores.rds
  │       ├── un_estructura_edad.parquet
  │       ├── dane_estructura_edad.rds
  │       ├── mundo_geom.rds
  │       ├── mundo_puntos.rds
  │       ├── wpp_pca_coordenadas_todo_periodo.parquet
  │       ├── wpp_matriz_arquetipos_proyecciones.parquet
  │       ├── wpp_transiciones_persistentes_globales.parquet
  │       └── 10_proyecciones_todos_los_metodos.rds
  │
  ├── R/
  │   ├── config.R
  │   ├── tema.R
  │   ├── utils_datos.R
  │   ├── utils_espacial.R
  │   └── mod_pca_clusters.R
  │
  ├── scripts/
  │   ├── 00_setup_exploracion_wpp2024.R          ✅
  │   ├── 01_viabilidad_propuesta.R               ✅
  │   ├── 02_universo_bandas_migracion.R          ✅
  │   ├── 02_pca_y_clustering.R                   ✅ Fase 2
  │   ├── 03_estructura_edad_onu_dane.R           ✅
  │   ├── 03b_diagnostico_edad_onu.R              ✅
  │   ├── 04_espacial_geometrias.R                ✅
  │   ├── 05_espacial_mapas.R                     ✅
  │   ├── 06_espacial_moran_lisa.R                ✅
  │   ├── 07_eda.R                                ✅ Fase 2
  │   ├── 10_series_tiempo_pronosticos.R          ✅ Fase 3
  │   ├── 11_integracion_series_tiempo.R          ✅ Fase 3
  │   └── pendientes: 15_incertidumbre_variantes.R
  │
  ├── app/
  │   ├── app_ts.R                            <- dashboard independiente (bs4Dash)
  │   ├── app_pca.R                           <- app independiente del PCA
  │   └── 🆕 unificada/
  │       ├── app_unificada.R                 <- punto de entrada (8 pestañas)
  │       ├── global.R                        <- carga única de datos
  │       └── modules/
  │           ├── mod_pca_clusters.R
  │           ├── 🆕 mod_series.R
  │           ├── 🆕 mod_discrepancias.R
  │           └── 🆕 mod_criticos.R
  │
  ├── reporte/
  │   └── reporte_wpp2024.Rmd
  └── output/
      ├── figuras/
      └── tablas/
```

## Hechos validados de los datos

Se mantienen los puntos 4.1 a 4.11 del README anterior. Se añaden:

### 4.12 EDA (script 07, universo de 161 países)

| Hallazgo | Valor |
|----|----|
| Mitad de los países bajo reemplazo (TFR \< 2.1) | 2022 |
| Mitad de la población mundial bajo reemplazo | 2020 |
| Colombia bajo reemplazo | 2009 |
| País con mayor velocidad de envejecimiento | Puerto Rico (6.4 años/década, máx. en 2024) |
| Colombia en velocidad de envejecimiento | puesto 22 (4.7 años/década, máx. en 2037) |
| Primer año con ≥ 50 % de países con Births \< Deaths | 2023 (53 de 237) |
| Año con más países en caída de LEx (≥ 1 año) | 2021 (52 países); 2020 (50 países) |
| Mayor caída de LEx país-año | RCA 2009 (−35.2 años); Ruanda 1994 (−30.8); Camboya 1975 (−26.5) |
| Pico de migración neta de Colombia | 496 mil en 2018; mínimo −98 mil en 1976 |
| Edad mediana de Colombia alcanza 40 años | 2042 (vs. 2049 ALC, 2080 mundo) |
| Edad mediana de Colombia alcanza 50 años | 2075 (ALC y mundo no alcanzan antes de 2100) |
| Grupos de indicadores redundantes (\|ρ\| medio ≥ 0.9, 2023) | TFR-NRR-Edad mediana-CBR-Crec. natural; LEx-LE60-IMR-Q5; CDR; CNMR; Crec. pob.; Índice vital; Ganancia 10a |

### 4.13 PCA longitudinal y arquetipos (script 02_PCA, 161 países × 141 años, 1960-2100)

| Elemento | Resultado |
|----|----|
| Panel balanceado | 161 países × 141 años (horizonte 1960-2100) |
| Variables del PCA | TFR, CBR, LEx, LE60, MedianAgePop, log(IRG), Velocidad_Envejecimiento |
| PC1 · Madurez estructural | correlación positiva con MedianAgePop (signo corregido) |
| PC2 · Dinámica / velocidad | carga alta de Velocidad_Envejecimiento |
| PC3 · Estructura (reemplazo) | balance natural |
| K elegido | 4 (justificado por silueta y por las 4 etapas de la transición demográfica) |
| Arquetipos | 1 = más joven → 4 = más envejecido (reordenados semánticamente por PC1 medio) |
| Transiciones persistentes | racha mínima de 3 años en el nuevo estadio |
| Colombia | trayectoria completa en `02_trayectoria_transicion_colombia.csv` |
| Sensibilidad de Colombia a K=3..6 | guardada en `02_sensibilidad_hito_colombia.csv` |

### 4.14 Pronósticos propios vs. ONU (script 10, 235 países, horizonte 77 años)

| Variable     | Método elegido (por MASE) | MASE global | \% ONU en IC95 propio |
|--------------|---------------------------|-------------|-----------------------|
| MedianAgePop | Estructural               | 3.75        | 94.5 %                |
| TFR          | Ensamble                  | 3.00        | 98.1 %                |
| LEx          | Ensamble                  | 2.37        | 97.6 %                |
| LE60         | GAM                       | 3.80        | 93.7 %                |
| LE65         | GAM                       | 3.86        | 92.3 %                |
| CBR          | GAM                       | 3.17        | 98.8 %                |
| IRG          | ETS                       | 4.75        | 88.0 %                |
| RS           | Ensamble                  | 4.13        | 92.7 %                |

Todos los métodos propios superan al naive de un paso (MASE naive ≥ 5 en todas las variables). LEx es la única con MASE \< 1 en horizonte corto (0.98).

### 4.15 Integración (script 11, regla D16)

| Variable | Bloque | \% país-año DENTRO de la banda 80 % oficial |
|----|----|----|
| TFR | 2024-2050 | 95.4 % |
| TFR | 2051-2075 | 96.0 % |
| TFR | 2076-2100 | 88.8 % |
| LEx | 2024-2050 | 91.2 % |
| LEx | 2051-2075 | 83.2 % |
| LEx | 2076-2100 | 69.6 % |
| MedianAgePop | 2024-2050 | 70.7 % |
| MedianAgePop | 2051-2075 | 72.7 % |
| MedianAgePop | 2076-2100 | 71.6 % |
| CBR | todos los bloques | ≥ 97.9 % |
| LE65 | todos los bloques | 0 % (el pronóstico propio está sistemáticamente por debajo de la banda oficial; ver D16) |

Conciliación de RS: la RS del portal de la ONU y el PSR65 del script 03 coinciden con mediana de diferencia relativa \< 0.02 % en el universo.

### 4.16 Triangulación del punto crítico de Colombia (RS 15-64/65+ \< 3)

| Fuente | Regla | Año |
|----|----|----|
| DANE (script 03) | 3 años seguidos bajo el umbral | 2058 |
| ONU Medium (script 03) | 3 años seguidos bajo el umbral | 2052 |
| ONU Medium (script 10) | se mantiene bajo el umbral hasta 2100 | 2052 |
| Propio, central (script 10) | se mantiene bajo el umbral hasta 2100 | 2047 |
| Propio, límite temprano (IC95) | banda inferior | 2033 |
| Propio, límite tardío (IC95) | banda superior | NA (no cruza antes de 2100) |

Universo (161 países): 82 cruzan en ambos (propio y ONU); mediana de diferencia = +1 año; 62.2 % de los países están a ≤ 5 años de diferencia entre el pronóstico propio y la ONU; 22 % cruza antes en el pronóstico propio.

## Registro de decisiones

Se mantienen D1-D27. Se añaden:

| \# | Decisión | Estado | Evidencia |
|----|----|----|----|
| D28 | Método de pronóstico por variable, elegido por MASE global del backtesting (no por parecido a la ONU) | ✅ Cerrada | `10_resumen_validacion.csv` |
| D29 | COVID-19 interpolado linealmente (2020-2021) SOLO en el entrenamiento de LEx, LE60, LE65 e IRG | ✅ Cerrada | `ANIOS_COVID`, `VARS_COVID` |
| D30 | IC empíricos del backtesting; cuantiles del error escalado; crecimiento √h tras horizonte validado (\~33 años) | ✅ Cerrada | `bandas()` |
| D31 | Punto crítico pensional = primer año desde el cual RS \< umbral se mantiene hasta 2100 | ✅ Cerrada | `10_puntos_criticos_RS.csv` |
| D32 | Límites demográficos por variable (p. ej. TFR ∈ [0.8, 8], LEx ∈ [30, 100]) | ✅ Cerrada | `LIMITES` |
| D33 | "Discrepancia" con la ONU = caer fuera de la banda oficial del 80 % [min, max] | ✅ Cerrada | `11_d16_posicion_vs_banda80.csv` |
| D34 | PCA sobre panel balanceado 1960-2100 (141 años) con log(IRG) y Velocidad_Envejecimiento | ✅ Cerrada | `02_pca_autovalores.csv` |
| D35 | K = 4 arquetipos (justificado por silueta y por las 4 etapas de la transición demográfica) | ✅ Cerrada | `02_metricas_diagnostico_siluetas.csv` |
| D36 | Arquetipos reordenados semánticamente por PC1 medio (1 = más joven → 4 = más envejecido) | ✅ Cerrada | `02_cluster_centroides.csv` |
| D37 | Transición de arquetipo = permanencia ≥ 3 años en el nuevo estadio (sensibilidad 1-8 años en la app) | ✅ Cerrada | `transiciones_persistentes()` |

## Cómo ejecutar

Orden actualizado:

```         
00 → 01 → 02 → 03b → 03 → 04 → 05 → 06 → 07 → 02_PCA → 10 → 11
```

🆕 Apps independientes: - `app_ts.R`: series de tiempo, discrepancias, puntos críticos, mapa, validación. - `app_pca.R`: varianza y cargas, trayectorias en el plano factorial, estadios, transiciones.

🆕 App unificada:

```         
shiny::runApp("app/unificada")
```

## Verificaciones

Se mantienen V1-V9. Se añaden:

| \# | Qué verificar | Por qué importa |
|----|----|----|
| V10 | En la salida del 10: MASE \< 7 para todas las variables y modelos propios; naive ≥ 5 | Los métodos propios superan al naive |
| V11 | En la salida del 11: % país-año DENTRO de la banda 80 % ≥ 70 % para TFR, LEx, MedianAgePop, CBR | El pronóstico propio es razonable vs. la incertidumbre oficial |
| V12 | LE65 está sistemáticamente por debajo de la banda oficial (0 % dentro) | Revisar si el GAM de LE65 necesita recalibración o si la banda oficial es demasiado estrecha |
| V13 | En la app_pca: las trayectorias de Colombia cruzan los estadios 1 → 2 → 3 → 4 en el orden esperado | Validación visual del reordenamiento semántico |
| 🆕 V14 | En la app unificada: los filtros globales (`g_paises`, `g_variable`, `g_anios`) afectan consistentemente a las pestañas Series, Discrepancias, Puntos críticos y Validación | Coherencia de UX |
| 🆕 V15 | La app unificada arranca en menos de 10 segundos con `waiter` y lectura diferida | Experiencia de usuario del video |

## Plan paso a paso

### FASE 2 · EDA + PCA ✅

-   Paso 7-10. ✅ EDA completo (`scripts/07_eda.R`).
-   Paso 12. ✅ PCA longitudinal (`scripts/02_pca_y_clustering.R`): varianza, cargas, círculo de correlación.
-   Paso 13. ✅ Clustering K=4 con justificación por silueta, reordenamiento semántico y transiciones persistentes.

### FASE 3 · Modelado ✅⬛

-   Paso 14. ✅ Pronósticos propios (`scripts/10_series_tiempo_pronosticos.R`): ETS, GAM, estructural; backtesting 1990/2000/2010; elección por MASE (D28); IC empíricos (D30); punto crítico pensional (D31). Bitácora en `ANALISIS_SERIES_TIEMPO.md`.
-   Paso 14b. ✅ Integración (`scripts/11_integracion_series_tiempo.R`): conciliación RS, regla D16, triangulación Colombia.
-   Paso 15. ⏳ Incertidumbre con OtherVariants: amplitud High-Low en 2100, ancho de intervalos 80 % y 95 %, cruce con los clusters del PCA.

### FASE 5 · App Shiny ✅⬛

-   Paso 19. ✅ Dos apps independientes (`app_ts.R`, `app_pca.R`).
-   🆕 Paso 19c. ⏳ App unificada: 4 módulos listos (`mod_series`, `mod_pca_clusters`, `mod_discrepancias`, `mod_criticos`); faltan `mod_mapa` y `mod_validacion`.

## App Shiny unificada: arquitectura actual

La app unificada combina lo mejor de `app_ts` (explorador de series, discrepancias, puntos críticos, mapa, validación) con lo mejor de `app_pca` (trayectorias en el plano factorial, estadios, transiciones) y añade los resultados del EDA y del análisis espacial. Construida sobre `bs4Dash` para mantener coherencia visual.

### 13.1 Estructura de pestañas

| \# | Pestaña | Origen | Contenido | Estado |
|----|----|----|----|----|
| 1 | Inicio | nueva | KPIs estáticos (países, edad mediana promedio 2100, cobertura ONU en IC95), pregunta central, leyenda de lecturas | ✅ |
| 2 | Explorador de series | `mod_series` | Selector de países (hasta 8), variable, histórico vs. proyección, IC95, promedio mundial | ✅ |
| 3 | Arquetipos demográficos | `mod_pca_clusters` | Círculo de correlación, trayectorias en el plano factorial, mapa de estadios por año, tabla de países por estadio | ✅ |
| 4 | Transiciones | `mod_pca_clusters` | Slider de racha (1-8 años), histograma de transiciones por década, tabla global, texto de Colombia | ✅ |
| 5 | Discrepancias vs. ONU | `mod_discrepancias` | Serie de discrepancias (propio − ONU), ranking de países, % dentro de la banda 80 % (D16) | ✅ |
| 6 | Puntos críticos | `mod_criticos` | Slider de umbral RS, gráfico de RS con 4 fuentes (ONU, DANE, propio, IC95), tabla de años críticos, triangulación de Colombia | ✅ |
| 7 | Mapa mundial | `app_ts` + script 05/06 | Animación año a año; capas: proyección propia, ONU, discrepancia, arquetipo, grupos LISA | ⏳ |
| 8 | Validación | `app_ts` | Boxplots de MASE por modelo y variable, tabla resumen | ⏳ |

### 13.2 Filtros globales (sidebar persistente)

```         
┌─────────────────────────────┐
│ 🌍 País foco                │
│ [selectize: hasta 8 países] │
│                             │
│ 📊 Indicador                │
│ [dropdown: 8 variables]     │
│                             │
│ 📅 Rango de años            │
│ [slider: 1950 - 2100]       │
│                             │
└─────────────────────────────┘
```

Los filtros globales afectan a las pestañas 2, 5, 6 y 8. Las pestañas 3, 4 y 7 tienen sus propios filtros específicos (ejes del PCA, racha de transición, año del mapa).

### 13.3 Módulos Shiny actuales

```         
app/unificada/
 ├── app_unificada.R              <- punto de entrada
 ├── global.R                     <- carga única de datos
 └── modules/
     ├── mod_series.R             ✅
     ├── mod_pca_clusters.R       ✅
     ├── mod_discrepancias.R      ✅
     ├── mod_criticos.R           ✅
     ├── mod_mapa.R               ⏳ (por crear)
     └── mod_validacion.R         ⏳ (por crear)
```

### 13.4 Datos que carga `global.R`

``` r
# Series de tiempo
ts_largo   <- read_csv("output/tablas/10_Proyecciones_Propias_vs_ONU_largo.csv")
ts_hist    <- read_csv("output/tablas/10_historico_largo.csv")
ts_valid   <- read_csv("output/tablas/10_validacion_por_pais.csv")
ts_crit    <- read_csv("output/tablas/10_puntos_criticos_RS.csv")
ts_d16     <- read_csv("output/tablas/11_d16_posicion_vs_banda80.csv")
ts_triang  <- read_csv("output/tablas/11_triangulacion_colombia_rs3.csv")
# PCA y arquetipos
pca_coord  <- arrow::read_parquet("data/clean/wpp_pca_coordenadas_todo_periodo.parquet")
pca_arq    <- arrow::read_parquet("data/clean/wpp_matriz_arquetipos_proyecciones.parquet")
pca_trans  <- arrow::read_parquet("data/clean/wpp_transiciones_persistentes_globales.parquet")
# Espacial
mundo_geom <- readRDS("data/clean/mundo_geom.rds")
lisa       <- read_csv("output/tablas/06_lisa_resultados.csv")
# DANE
dane       <- readRDS("data/clean/dane_estructura_edad.rds")
```

### 13.5 Recomendaciones de UX para el video

-   Tour guiado de 60 segundos en la pestaña de inicio: resalta cada pestaña en orden con `shinyjs::addClass` secuencial.
-   Animación del mapa con `animationOptions(interval = 700)` y botón ▶ visible; empezar en 1950 y correr hasta 2100.
-   Tooltips unificados con `hover = "x unified"` en plotly para que el cursor muestre todos los países a la vez.
-   Descargas contextuales: cada pestaña con su propio `downloadButton` que exporta solo los datos filtrados.
-   Leyenda de lecturas fija en la parte inferior de cada pestaña (como en `app_ts`): "Línea continua = observado; continua naranja = propio; discontinua = ONU; banda = IC95".
-   Colores consistentes con `R/tema.R`: azul = estimación, naranja = proyección, bermellón = acento; Okabe-Ito para categorías.
-   Colombia siempre resaltada en mapas y gráficos de series (principio del proyecto).
-   Carga inicial \< 5 segundos: usar `waiter` con un spinner y precargar solo los CSV pequeños; los parquet se leen con `arrow` bajo demanda.

### 13.6 Guion sugerido para el video (3-4 minutos)

| Segundo | Pantalla | Mensaje |
|----|----|----|
| 0-15 | Inicio | Pregunta central: "¿Qué tan rápido, y con cuánta incertidumbre, envejecerá Colombia hasta 2100 frente al mundo?" |
| 15-45 | Explorador de series | Seleccionar Colombia + 2 países de referencia; mostrar histórico + pronóstico propio + ONU + IC95 |
| 45-75 | Arquetipos | Círculo de correlación → trayectorias de Colombia en el plano factorial → mapa de estadios en 2050 |
| 75-105 | Transiciones | Slider de racha = 3 años; histograma por década; texto de Colombia: "cruza del estadio 2 al 3 en 20XX" |
| 105-135 | Discrepancias + D16 | Serie de discrepancias; mostrar que \> 90 % de las proyecciones propias caen dentro de la banda oficial del 80 % |
| 135-165 | Puntos críticos | Triangulación de Colombia: DANE 2058, ONU 2052, propio 2047, IC temprano 2033 |
| 165-195 | Mapa mundial | Animación 1950 → 2100 con capa de arquetipos; bloque europeo y africano |
| 195-225 | Validación | Boxplots de MASE: todos los métodos propios superan al naive |
| 225-240 | Cierre | "Código reproducible, registro de decisiones y app interactiva en github.com/..." |

## Riesgos y problemas conocidos

| Riesgo o síntoma | Causa | Solución |
|----|----|----|
| LE65 cae sistemáticamente fuera de la banda oficial del 80 % | El GAM de LE65 proyecta valores más bajos que los de la banda oficial | Revisar si la banda oficial de LE65 es demasiado estrecha o si el GAM necesita recalibración (V12) |
| IRG con 3.67 % de pronósticos en tope (0.05 o 10) | Alta volatilidad del índice Births/Deaths | Límites demográficos (D32); reportar como diagnóstico |
| El conteo de LISA en 2100 varía entre semillas (37-49) | Azar de las permutaciones + BH cerca del umbral | Reportar como rango (D24) |
| 🆕 La app unificada puede tardar \> 10 s en cargar | Muchos parquet y CSV | `waiter` + lectura diferida por pestaña (V15) |
| 🆕 Los módulos `mod_mapa` y `mod_validacion` aún no existen | Pendiente de migrar desde `app_ts` | Crear como siguientes pasos de la Fase 5 |
| 🆕 El archivo `poblacion_por_edad.csv` no está en `data/raw/` | La RS no se calcula en el script 10 | Descargar del portal de la ONU y documentar en `FUENTES.md` |

## Citación de los datos

United Nations, Department of Economic and Social Affairs, Population Division (2024). *World Population Prospects 2024*, Online Edition. Licencia CC BY 3.0 IGO.

American Statistical Association (2022). *Ethical Guidelines for Statistical Practice*. <https://doi.org/10.5281/zenodo.7092386>

DANE, Dirección de Censos y Demografía. *Proyecciones de población nacionales por área, sexo y edad (PPED)*: archivo 1950-2017 (actualización de marzo de 2023) y archivo 2018-2070 (actualizado el 18 de julio de 2025).

Natural Earth. *Admin 0 - Countries*, escala 1:50m, vía `rnaturalearth` 1.2.0 y `rnaturalearthdata` 1.0.0.
