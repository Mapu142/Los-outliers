# ASA DataQuest 2026 · UN World Population Prospects 2024

Guía de navegación, registro de hallazgos y plan de trabajo del proyecto. **Léela completa antes de escribir código nuevo** y actualízala al cerrar cada fase.

> **Estado actual:** Fase 0 completa. Fase 1 en curso: pregunta central y plan analítico en [`PLAN_ANALITICO.md`](PLAN_ANALITICO.md); decisiones D9-D18 propuestas en `DECISIONES.md`. Siguiente: ejecutar `scripts/02_universo_bandas_migracion.R` y descargar las fuentes externas E1 y E2.

---

## 1. Objetivo

Construir un análisis ganador del concurso ASA DataQuest 2026 con los datos WPP 2024 de la ONU, entregando:

1. Un **reporte R Markdown interactivo** (introducción, metodología, hallazgos, recomendaciones).
2. Una **aplicación Shiny** modular (filtros, simulación, descargas).
3. Un **código reproducible** y un registro de decisiones, alineados con las *Ethical Guidelines for Statistical Practice* de la ASA (2022).

Principio rector: **una pregunta central bien respondida** vale más que muchos análisis dispersos. El archivo Medium basta para una entrega sólida; OtherVariants es opcional y sirve para la incertidumbre.

---

## 2. Estado del proyecto

| Fase | Contenido | Estado |
|---|---|---|
| 0 | ETL, validación, parquet limpio, tema visual | ✅ Completa |
| 1 | Pregunta central, plan analítico y datos externos | ⏳ En curso |
| 2 | EDA | ⬜ |
| 3 | Modelado e incertidumbre | ⬜ |
| 4 | Reporte Rmd | ⬜ |
| 5 | App Shiny | ⬜ |
| 6 | Cierre y revisión ética | ⬜ |

**Casillas pendientes de la Fase 0:**
- [ ] Paso 1: confirmar que la estructura de carpetas existe tal como el punto 3.
- [x] Paso 2: script 00 ejecutado desde cero sin errores.
- [x] Paso 3: `R/config.R`, `R/utils_datos.R` y `R/tema.R`.
- [x] Paso 4: `DECISIONES.md` creado (D1-D7 cerradas; D8-D11 abiertas).

---

## 3. Estructura de carpetas

```
proyecto-wpp2024/
├── README.md                      <- este archivo
├── DECISIONES.md                  <- registro de decisiones (Paso 4)
├── proyecto-wpp2024.Rproj
│
├── data/
│   ├── raw/                       <- archivos originales, SOLO LECTURA, nunca editar
│   │   ├── WPP2024_Demographic_Indicators_Medium_csv.gz
│   │   ├── WPP2024_Demographic_Indicators_OtherVariants_csv.gz
│   │   ├── WPP2024_Demographic_Indicators_notes.csv
│   │   ├── WPP2024_Supplement_Births_and_LE60.csv
│   │   └── externos/                <- fuentes externas + FUENTES.md (registro obligatorio)
│   └── clean/                     <- salidas generadas por scripts (regenerables)
│       ├── wpp_paises_medium_suppl.parquet    <- 35,787 filas (237 países × 1950-2100)
│       ├── diccionario_indicadores.rds
│       └── (features, clusters, modelos, etc.)
│
├── R/                             <- funciones reutilizables (no ejecutan nada al cargarse)
│   ├── config.R                   <- CFG, rutas, paleta, constantes
│   ├── tema.R                     <- theme_dataquest() y escalas de color
│   ├── utils_datos.R              <- conexión duckdb, helpers SQL, ver()
│   └── utils_modelos.R            <- PCA, clustering, métricas
│
├── scripts/                       <- pipeline numerado, se ejecuta en orden
│   ├── 00_setup_exploracion_wpp2024.R
│   ├── 01_eda.R
│   ├── 02_features.R
│   ├── 03_pca_clustering.R
│   ├── 04_modelos_gam_ts.R
│   └── 05_incertidumbre_variantes.R
│
├── reporte/
│   └── reporte_wpp2024.Rmd
├── app/
│   ├── ui.R
│   ├── server.R
│   ├── global.R
│   └── modules/
└── output/
    ├── figuras/
    └── tablas/
```

**Reglas de navegación**
- `data/raw` nunca se modifica. Todo lo derivado vive en `data/clean`.
- Cada script de `scripts/` lee la salida del anterior. Tras el script 00, **nadie vuelve a leer los `.gz`**, salvo `05` para OtherVariants.
- Las funciones van en `R/`; los scripts solo las llaman.
- El Rmd y la app **no recalculan** modelos pesados: leen resultados guardados.

---

## 4. Hechos validados de los datos

Todo lo siguiente proviene de la ejecución real del script 00.

### 4.1 Archivo Medium

| Hecho | Valor |
|---|---|
| Filas | 84,360 |
| Ubicaciones | 555 = 237 países/áreas con ISO3 + 318 agregados |
| Rango temporal | 1950-2101 |
| Columnas | 67 = 13 de identificación + 54 indicadores |
| Variante | Solo "Medium" |
| Llave `(LocID, Time)` | Única, sin duplicados |
| Suma de países frente a fila `World` | Diferencia 0.0000 % en 1950-2100 (sin doble conteo) |
| `LocTypeName` | 234 ubicaciones con `NA` y sin ISO3 (grupos ad hoc): **no usar para filtrar** |
| Variables del suplemento en Medium | Ninguna (confirmado) |

### 4.2 El año 2101 está casi vacío

En 2101 las 237 filas de países solo traen `TPopulation1Jan`. `TPopulation1July`, `TFR`, `LEx` y `Births` tienen 0 valores (2099 y 2100 están completos). Por eso la prueba contra `World` daba `NA` solo en 2101. **El análisis llega hasta 2100.** Falta verificar el mismo patrón en OtherVariants (ver punto 7).

### 4.3 Faltantes: un solo indicador

Tras recortar a 2100, **52 de 54 indicadores están completos** para los 237 países. `TPopulation1Jan` también está completo; el único con faltantes es `DoublingTime` (15,938 filas, 44.5 %).

`DoublingTime` presenta **censura estructural**, no faltantes aleatorios:

| Condición | Resultado |
|---|---|
| `PopGrowthRate ≤ 0` | Siempre `NA` (10,604 de 10,604) |
| `PopGrowthRate > 0` y ≤ 0.5 | Siempre `NA` (1,757 en estimaciones + 3,577 en proyecciones = 5,334) |
| `PopGrowthRate > 0.5` | Siempre con dato |

El umbral de 0.5 % es idéntico en estimaciones y proyecciones, y los rangos no se solapan (a la precisión de 4 decimales de la consulta).

### 4.4 Suplemento (Births by sex + LE60)

| Chequeo | Resultado |
|---|---|
| Dimensiones | 35,636 filas, 236 países, 1950-2100 |
| Países de Medium sin suplemento | Solo Holy See (LocID 336, `VAT`) |
| `LE60` faltante tras la unión | Solo Holy See, 151 filas |
| `LE60` entre `LE60Male` y `LE60Female` | 0 incoherentes |
| `BirthsMale + BirthsFemale` frente a `Births` | Diferencia máxima 0.001; 0 filas por encima de 0.0011 |

Con tolerancia de 0.001, el chequeo marcaba 4,852 filas (13.6 %): era un artefacto de punto flotante (diferencias de exactamente 0.001), no una inconsistencia del suplemento. La tolerancia correcta es **0.0011**.

### 4.5 OtherVariants

| Grupo | Variantes | Ubicaciones | Años | Filas por variante |
|---|---|---|---|---|
| Escenarios (12) | Accelerated ABR decline; Accelerated ABR decline with rec; Constant fertility; Constant mortality; High; Instant replacement; Instant replacement zero migration; Low; Momentum; No change; No fertility below age 18; Zero migration | 555 | 2024-2101 | 43,290 |
| Intervalos (5) | Lower 80 PI; Upper 80 PI; Lower 95 PI; Upper 95 PI; Median PI | 321 | 2024-2101 | 25,038 |
| Promedio (1) | Mean | 237 (solo países) | 2024-2100 | 18,249 |

Notas:
- El total es 12 escenarios + 5 intervalos + 1 promedio = 18 variantes, igual que el conteo de `var_tab`.
- Los intervalos existen para **321 ubicaciones** = 237 países + 84 agregados. Cubren todos los países.
- "No change" y "Accelerated ABR decline" no aparecían en la lista de ejemplos de la guía; los nombres se usan tal como figuran en el archivo.
- Todas son proyecciones (2024+); no hay estimaciones en este archivo.
- **Indicadores por variante:** los escenarios traen los 54, salvo `Constant mortality` (30). Los intervalos traen 47 (faltan `NRR`, `SRB`, `DeathsMale`, `DeathsFemale`, `InfantDeaths`, `LBsurvivingAge1`, `Under5Deaths`). `Mean` trae solo `TFR`, `LExMale` y `LExFemale`.
- **`Mean` no es igual a `Medium`:** la diferencia absoluta máxima en `TFR` es 0.274.
- **Año 2101:** en todas las variantes solo existe `TPopulation1Jan`, igual que en Medium.

### 4.6 Instantánea de 2023 (países, medianas **no ponderadas** por población)

| Indicador | Valor |
|---|---|
| Países | 237 |
| TFR mediano | 1.95 (ya por debajo del nivel de reemplazo, 2.1) |
| Esperanza de vida al nacer mediana | 75.3 años |
| Edad mediana (mediana entre países) | 32.1 años |
| Población mundial (suma de países) | 8.09 mil millones |

Al ser medianas entre países, cada país pesa igual sin importar su tamaño. Esto es relevante para decidir si el análisis será por país o ponderado por población (D9).

### 4.7 Archivo guardado

`data/clean/wpp_paises_medium_suppl.parquet`: 35,787 filas = 237 países × 151 años. Incluye los 54 indicadores, las 5 variables del suplemento y la columna `tipo_dato` (Estimación / Proyección).

---

## 5. Registro de decisiones

| # | Decisión | Estado | Evidencia |
|---|---|---|---|
| D1 | Países = `ISO3_code` no nulo (237, incluye Holy See) | ✅ Cerrada | Diferencia 0.0000 % con `World` |
| D2 | Estimación `Time ≤ 2023`; proyección `Time ≥ 2024`, columna `tipo_dato` | ✅ Cerrada | Convención del archivo |
| D3 | Análisis hasta 2100; 2101 solo trae `TPopulation1Jan` | ✅ Cerrada | `diag_final` |
| D4 | Holy See sin suplemento: excluir de análisis con `LE60` o nacimientos por sexo | ✅ Cerrada | `sin_suppl`, `chk_le60_na` |
| D5 | Agregados solo como referencia; nunca sumados con países | ✅ Cerrada | Prueba contra `World` |
| D6 | Sin imputación. `DoublingTime` censurado cuando el crecimiento ≤ 0.5 %; no entra en PCA ni clustering; solo uso descriptivo con nota | ✅ Cerrada | Consultas de la sección 6 |
| D7 | Tolerancia de nacimientos = 0.0011 (artefacto de punto flotante) | ✅ Cerrada | `dif_max = 0.001`, 0 fuera de 0.0011 |
| D8 | OtherVariants: países por ISO3, análisis hasta 2100, intervalos con 47 indicadores, `Mean` no sustituye a Medium | ✅ Cerrada | Sección 10 del script 00 |
| D9 | ¿Análisis por país (peso igual) o ponderado por población? Definirlo por tipo de pregunta | ⏳ Fase 1 | Ver 4.6 |
| D10 | Selección de indicadores para PCA/clustering (excluir redundantes y `DoublingTime`) | ⏳ Fase 1 | Paso 6 |

---

## 6. Cómo ejecutar

1. Abrir `proyecto-wpp2024.Rproj` en RStudio.
2. Colocar los 4 archivos en `data/raw/`.
3. Ejecutar `scripts/00_setup_exploracion_wpp2024.R` **de arriba hacia abajo** (no saltar secciones: las vistas dependen del orden).
4. Las verificaciones `stopifnot()` detienen el script si algo estructural falla.
5. Al terminar existe `data/clean/wpp_paises_medium_suppl.parquet`, fuente única para el resto del proyecto.

**Cambios aplicados al script 00 respecto a la primera versión** (tu copia local debe tenerlos):
- Función auxiliar `ver()` para imprimir `data.frame` completos (reemplaza `print(x, n = Inf)`).
- `CFG$ultimo_anio_analisis = 2100L` y filtro `WHERE m.Time <= ...` en la vista `wpp_paises`.
- `CFG$tol_births = 0.0011`.
- `max(..., na.rm = TRUE)` y `stopifnot(< 0.01)` en la prueba contra `World`.
- Diagnóstico `diag_final` de los años 2099-2101.
- Chequeos 7.1 y 7.2 sobre `medium_paises` (no sobre `wpp_paises`, que se crea después).
- Eliminada la consulta `na_2101`, que quedó sin sentido tras el filtro.

Paquetes base: `DBI`, `duckdb`, `dplyr`, `tidyr`, `ggplot2`, `glue`, `scales`, `tibble`. Más adelante: `plotly`, `DT`, `reactable`, `bslib`, `flexdashboard`, `shiny`, `waiter`, `shinyjs`, `mgcv`, `forecast`, `cluster`, `factoextra`. Al final: `renv::snapshot()`.

---

## 7. Verificaciones

**Resueltas con la sección 10 del script 00:** V2 a V5 (ver 4.5 y D8). Queda V1 (revisar visualmente los gráficos).

| # | Qué verificar | Por qué importa |
|---|---|---|
| V1 | Revisar visualmente los dos gráficos de control de la sección 9 (población mundial; TFR por año) | Detectar problemas que los números no muestran |
| V2 | ¿Qué indicadores traen valores en OtherVariants, por variante? | Define qué incertidumbre se puede medir (p. ej. ¿hay `TFR` en los intervalos?) |
| V3 | ¿Cuántas de las 321 ubicaciones con intervalos son países? | Define la cobertura del análisis de incertidumbre |
| V4 | ¿Qué trae 2101 en OtherVariants? | Evitar usar un año incompleto |
| V5 | ¿`Mean` coincide con `Medium` o es otra cosa? | No asumir que son equivalentes |

Consulta sugerida para V2-V4 (ejecutar sobre `other_raw`):

```r
# Perfil de OtherVariants: filas con valor por variante y año final
ver(dbGetQuery(con, "
  SELECT Variant,
         SUM(CASE WHEN ISO3_code IS NOT NULL AND TRIM(ISO3_code) <> '' THEN 1 ELSE 0 END) AS filas_pais,
         COUNT(DISTINCT CASE WHEN ISO3_code IS NOT NULL AND TRIM(ISO3_code) <> ''
                             THEN LocID END) AS paises,
         SUM(CASE WHEN TPopulation1July IS NOT NULL THEN 1 ELSE 0 END) AS con_pob_1jul,
         SUM(CASE WHEN TFR              IS NOT NULL THEN 1 ELSE 0 END) AS con_tfr,
         SUM(CASE WHEN LEx              IS NOT NULL THEN 1 ELSE 0 END) AS con_lex,
         SUM(CASE WHEN Time = 2101 AND TPopulation1July IS NOT NULL THEN 1 ELSE 0 END) AS pob_en_2101
  FROM other_raw GROUP BY 1 ORDER BY 1"))
```

---

## 8. Plan paso a paso

Cada fase termina con un **entregable verificable** y un **criterio de cierre**. No se avanza sin cumplirlo.

### FASE 0 · Cimientos

**Paso 1.** Crear proyecto y estructura de carpetas. *Entregable:* carpetas del punto 3.

**Paso 2.** ✅ Script 00 completo. *Resultado:* parquet generado; D1-D7 cerradas.

**Paso 3.** Crear `R/config.R` y `R/tema.R`.
- `CFG` único (rutas, `ultimo_anio_estimado = 2023`, `ultimo_anio_analisis = 2100`, `tol_births = 0.0011`).
- Paleta Okabe-Ito fija; un color por región geográfica y uno para estimación/proyección.
- `theme_dataquest()`: tipografía limpia, sin cuadrícula innecesaria, títulos y subtítulos informativos, unidades en ejes.
- *Criterio de cierre:* gráfico de prueba (el de población mundial) reconstruido con el tema.

**Paso 4.** Volcar el punto 5 a `DECISIONES.md`, con fecha y alternativa descartada por decisión.

### FASE 1 · Pregunta y diseño

**Paso 5. Pregunta central.** Propuesta: *¿existen tipos de trayectorias demográficas entre países cuando se combinan fecundidad, mortalidad y migración, y qué tan incierto es el futuro de cada tipo?*

**Paso 6. Plan analítico previo (ASA B3, C3).** Escribirlo **antes** de analizar:
- Análisis exploratorios y confirmatorios.
- Número de comparaciones y control.
- Indicadores de PCA/clustering (D10): evitar redundancia (no mezclar `LEx`, `LExMale` y `LExFemale`; evitar `Births` junto a `CBR`; excluir `DoublingTime`).
- Ponderación por población (D9).

*Criterio de cierre:* plan de una página en `DECISIONES.md` con D8, D9 y D10 cerradas.

### FASE 2 · EDA (`scripts/01_eda.R`)

**Paso 7.** Tendencias globales y regionales, con quiebre estimación/proyección.
**Paso 8.** Transición demográfica: TFR frente a LEx, edad mediana, reemplazo (TFR = 2.1; NRR = 1). Aprovechar el hallazgo de 4.6: la mediana de TFR en 2023 ya está bajo el reemplazo.
**Paso 9.** Correlaciones en un año de referencia, con indicadores no redundantes.
**Paso 10.** Quiebres históricos: caídas anómalas de `LEx` y picos de migración neta (COVID-19, conflictos), listados con año y magnitud.

*Criterio de cierre:* 6-8 figuras finales en `output/figuras/` y lista de hallazgos candidatos.

### FASE 3 · Modelado

**Paso 11.** Características por país (`02_features.R`): niveles en años de referencia, cambios 1950→2023, pendientes recientes. Estandarizar y guardar.
**Paso 12.** PCA (`03_pca_clustering.R`): varianza explicada, cargas e interpretación; supuesto de linealidad.
**Paso 13.** Clustering: k-means y jerárquico; k por silueta, estabilidad por remuestreo y sentido sustantivo; `set.seed(2026)`.
**Paso 14.** Modelos complementarios (`04_modelos_gam_ts.R`): GAM (edf, R² ajustado, AIC, RMSE) y series de tiempo solo si aportan, ajustadas sobre **estimaciones** y contrastadas con la proyección de la ONU.
**Paso 15a.** Perfilar OtherVariants (verificaciones V2-V5) y cerrar D8.
**Paso 15b.** Incertidumbre (`05_incertidumbre_variantes.R`):
- SQL sobre OtherVariants; a R solo llegan agregaciones.
- Amplitud relativa entre `High` y `Low` en 2100 y ancho de los intervalos de 80 % y 95 % (solo donde existan).
- Cruzar con los clusters del Paso 13.
- Dejar claro que los escenarios **no son probabilidades** y que los intervalos probabilísticos tienen supuestos propios.

*Criterio de cierre:* tabla de métricas, interpretación y limitaciones por modelo.

### FASE 4 · Reporte (`reporte/reporte_wpp2024.Rmd`)

**Paso 16.** Estructura: resumen ejecutivo; introducción y pregunta; datos y metodología (D1-D10); hallazgos con `.tabset`; incertidumbre y limitaciones; recomendaciones; anexo técnico.
**Paso 17.** Interactividad solo donde aporta (tooltips, filtro por país). Cada gráfico con título, subtítulo con el mensaje, fuente y unidades.
**Paso 18.** Renderizado desde cero, usando solo `data/clean`.

### FASE 5 · App Shiny (`app/`)

**Paso 19.** Arquitectura modular: un módulo por pestaña y `global.R` con datos cargados una sola vez.
**Paso 20.** Filtros por ISO3, años (1950-2100) e indicadores; panel de simulación; descargas; `waiter`.
**Paso 21.** Pruebas de casos límite: un solo país, un solo año, indicador `DoublingTime` con censura, Holy See.

### FASE 6 · Cierre

**Paso 22.** Revisión ética con el punto 9.
**Paso 23.** Reproducibilidad: `renv::snapshot()`, `sessionInfo()`, README actualizado.
**Paso 24.** Lectura externa: alguien que no conozca el proyecto explica el hallazgo principal.

---

## 9. Lista de verificación ética (ASA 2022)

| Principio | Cómo se cumple |
|---|---|
| B1 Fuentes y fitness for use | Punto 4 de este README y sección "Datos" del Rmd; cita a la ONU (CC BY 3.0 IGO) |
| B1 Procesamiento y faltantes | D1-D10; censura de `DoublingTime` documentada |
| B2 Supuestos y limitaciones | Sección de limitaciones por modelo |
| B3 A priori vs. post hoc; comparaciones múltiples | Plan analítico del Paso 6 |
| C3 Exploratorio vs. confirmatorio | Etiquetar cada hallazgo |
| A4 No seleccionar resultados convenientes | Reportar también los análisis que no funcionaron |
| D6 Impacto sobre grupos | Nombres descriptivos y no estigmatizantes para los clusters de países |
| F4 Reproducibilidad | Scripts numerados, semillas, `renv` |

---

## 10. Convenciones

- Idioma: comentarios y texto en español; nombres de variables de la ONU sin traducir.
- Objetos en `snake_case`; funciones con verbo (`calcular_amplitud_variantes()`).
- Semilla: `set.seed(2026)`, registrada.
- Estimación frente a proyección siempre visible (línea punteada en 2023/2024 o patrón de color).
- Unidades: población y nacimientos en **miles**; TFR en hijos por mujer; edades en años.
- Nunca sumar países con agregados regionales.

---

## 11. Riesgos y problemas conocidos

| Riesgo o síntoma | Causa | Solución |
|---|---|---|
| Doble conteo de población | Mezclar países con agregados | Filtrar por ISO3 y correr la prueba contra `World` |
| Tratar proyecciones como observaciones | Falta de marca temporal | Columna `tipo_dato` en todo análisis |
| Año 2101 incompleto | Solo trae `TPopulation1Jan` | D3: análisis hasta 2100 |
| Holy See sin suplemento | No estaba en las descargas del portal | D4: excluir de análisis con suplemento |
| `DoublingTime` con 44.5 % de `NA` | Censura por crecimiento ≤ 0.5 % | D6: no imputar ni usar en modelos |
| Sobreinterpretar escenarios como probabilidades | Escenarios ≠ distribución | Redacción explícita en el reporte |
| Medianas engañosas | Países pequeños pesan igual que grandes | D9: decidir ponderación |
| Clusters inestables | Elección arbitraria de k | Silueta + remuestreo + semilla fija |
| `font family not found in Windows font database` | Fuente no registrada en el dispositivo gráfico de Windows | `fuente_dq()` usa `"sans"` por defecto; para otra fuente, backend AGG + `options(dq.fuente = "Inter")` |
| `invalid 'na.print' specification` | `print(df, n = Inf)` sobre `data.frame` base | Usar `ver(df)` |
| `max()` devuelve `NA` | Hay `NA` en el vector | `max(x, na.rm = TRUE)` |
| `object 'chk_mundo' not found` | Ejecutar un bloque sin correr antes la consulta que lo crea | Ejecutar el script de arriba hacia abajo |
| `Table ... does not exist` | Usar una vista antes de crearla (`wpp_paises` se crea en la sección 7.4) | Respetar el orden de las secciones |
| 4,852 filas "fuera de tolerancia" en nacimientos | Punto flotante con tolerancia 0.001 | Tolerancia 0.0011 (D7) |

---

## 12. Citación de los datos

United Nations, Department of Economic and Social Affairs, Population Division (2024). *World Population Prospects 2024, Online Edition.* Licencia CC BY 3.0 IGO.

American Statistical Association (2022). *Ethical Guidelines for Statistical Practice.* https://doi.org/10.5281/zenodo.7092386