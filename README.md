# ASA DataQuest 2026 · UN World Population Prospects 2024

Guía de navegación, registro de hallazgos y plan de trabajo del proyecto. **Léela completa antes de escribir código nuevo** y actualízala al cerrar cada fase.

> **Estado actual (28-oct-2026):** Fase 0 completa. Fase 1 casi cerrada: plan analítico (`PLAN_ANALITICO.md`), estructura por edad de la ONU y del DANE (scripts 03 y 03b) y datos externos E1, E2 y E5 cargados y verificados. **Ampliación espacial en curso** (scripts 04 a 06, exploratoria; ver `ANALISIS_ESPACIAL.md`). Siguiente: re-ejecutar 04 y 05 con las correcciones de geometría (D22: error de `st_cast` hallado en la 2ª ejecución del 04), anexar D19-D25 a `DECISIONES.md` y pasar a la EDA (Fase 2).

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
| 1 | Pregunta central, plan analítico y datos externos | ⏳ Casi cerrada |
| 1b | Ampliación espacial: geometrías, mapas, Moran y LISA | ⏳ Re-ejecutar 04, 05 y 06 tras la corrección de D22 |
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

**Casillas de la Fase 1 y de la ampliación espacial:**
- [x] Plan analítico previo (`PLAN_ANALITICO.md`, 20-oct-2026).
- [x] Scripts 01 (viabilidad) y 02 (universo, orden de bandas PI, efecto de la migración).
- [x] Script 03: estructura por edad ONU y DANE, empalme y puntos de control (lectura robusta de los dos Excel).
- [x] Script 03b: diagnóstico que cerró las tres alertas del 03.
- [x] Script 04: geometrías Natural Earth y cruce por ISO3.
- [x] Script 05 (mapas) y script 06 (Moran global, LISA y sensibilidad a k).
- [ ] Re-ejecutar 04, 05 y 06 con la corrección de `a_partes()` (D22), registrar la corrida C en `ANALISIS_ESPACIAL.md` y revisar los PNG (V6-V8).
- [ ] Anexar D19-D25 a `DECISIONES.md` y completar `FUENTES.md` (E1, E2, E5).
- [ ] Confirmar con las salidas del script 02 las decisiones D12, D14 y D17.

---

## 3. Estructura de carpetas

```
proyecto-wpp2024/
├── README.md                      <- este archivo
├── DECISIONES.md                  <- registro de decisiones (Paso 4)
├── PLAN_ANALITICO.md              <- plan previo (pasos 5 y 6)
├── ANALISIS_ESPACIAL.md           <- bitácora del análisis espacial (corridas, observaciones)
├── proyecto-wpp2024.Rproj
│
├── data/
│   ├── raw/                       <- archivos originales, SOLO LECTURA, nunca editar
│   │   ├── WPP2024_Demographic_Indicators_Medium_csv.gz
│   │   ├── WPP2024_Demographic_Indicators_OtherVariants_csv.gz
│   │   ├── WPP2024_Demographic_Indicators_notes.csv
│   │   ├── WPP2024_Supplement_Births_and_LE60.csv
│   │   └── externos/              <- fuentes externas + FUENTES.md (registro obligatorio)
│   │       ├── FUENTES.md
│   │       ├── WPP2024_PopulationBySingleAgeSex_Medium_*.csv   (E1: ONU por edad simple)
│   │       ├── PPED-AreaSexoEdadNac-1950-2017.xlsx             (E2: DANE, actualización de marzo de 2023)
│   │       ├── PPED-AreaSexoEdadNac-2018-2070.xlsx             (E2: DANE, actualizado el 18 de julio de 2025)
│   │       ├── natural_earth_admin0_50m.gpkg                   (E5: copia generada por el script 04)
│   │       └── documentacion/     <- PDF del DANE (marzo de 2023) y checkpoints_dane.csv
│   └── clean/                     <- salidas generadas por scripts (regenerables)
│       ├── wpp_paises_medium_suppl.parquet    <- 35,787 filas (237 países × 1950-2100)
│       ├── diccionario_indicadores.rds
│       ├── un_estructura_edad.parquet         <- ONU por grandes grupos de edad y PSR (script 03)
│       ├── dane_estructura_edad.rds           <- DANE empalmado 1950-2070 (script 03)
│       ├── mundo_geom.rds                     <- polígonos por ISO3 (script 04)
│       ├── mundo_puntos.rds                   <- punto representativo por país (script 04)
│       └── (features, clusters, modelos, etc.)
│
├── R/                             <- funciones reutilizables (no ejecutan nada al cargarse)
│   ├── config.R                   <- CFG, rutas, paleta, constantes
│   ├── tema.R                     <- theme_dataquest() y escalas de color
│   ├── utils_datos.R              <- conexión duckdb, helpers SQL, ver()
│   ├── utils_espacial.R           <- kNN, Moran global y local, a_partes(), reparación de geometrías, mapas
│   └── utils_modelos.R            <- PCA, clustering, métricas (pendiente)
│
├── scripts/                       <- pipeline numerado, se ejecuta en orden
│   ├── 00_setup_exploracion_wpp2024.R     ✅ ETL, validación, parquet
│   ├── 01_viabilidad_propuesta.R          ✅ qué se puede hacer con los archivos
│   ├── 02_universo_bandas_migracion.R     ✅ universo, orden de bandas PI, migración
│   ├── 03_estructura_edad_onu_dane.R      ✅ PSR de la ONU y del DANE, empalme, puntos de control
│   ├── 03b_diagnostico_edad_onu.R         ✅ diagnóstico que cerró las alertas del 03
│   ├── 04_espacial_geometrias.R           ✅ fronteras y cruce por ISO3
│   ├── 05_espacial_mapas.R                ✅ mapas coropléticos descriptivos
│   ├── 06_espacial_moran_lisa.R           ✅ Moran, LISA, sensibilidad, figuras y resumen .md
│   └── pendientes (numeración tentativa): 07_eda · 08_features · 09_pca_clustering ·
│                                          10_modelos_gam_ts · 11_incertidumbre_variantes
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

### 4.8 Estructura por edad de la ONU (scripts 03 y 03b)

| Chequeo | Resultado |
|---|---|
| Suma por edades frente a `TPopulation1July` | Mediana de la diferencia relativa 7.6e-7; máximo 2.2 %, solo en micro-estados (Holy See, ~0.5 mil habitantes) |
| Misma prueba en el universo (≥ 1 millón) | Diferencia relativa máxima 1.5e-5 (17 personas) |
| Mediana calculada − `MedianAgePop` | **+1.00 año**, desviación 0.02; 99.1 % de las filas dentro de 1.0 ± 0.1; 237 países y todo el periodo. Es un desfase de convención (D21) |
| Colombia (ONU), mediana calculada / PSR 15-64 por 65+ | 2023: 32.6 / 7.47 · 2035: 38.2 / 4.64 · 2050: 44.7 / 3.15 · 2070: 50.0 / 1.81 · 2100: 52.8 / 1.48 |
| Países que cruzan PSR65 < 3.0 entre 2023 y 2100 | 168 de 237 |

### 4.9 Proyecciones del DANE (E2): estructura real de los archivos

| Archivo | Hoja de datos | Encabezado | Versión declarada |
|---|---|---|---|
| 1950-2017 | `Nacional_1950_2017` | Una fila: DP, DPNOM, AÑO, ÁREA GEOGRÁFICA, `Hombres_0`…; 3 filas por año (Cabecera, Centros Poblados y Rural Disperso, Total); pies de nota al final | Actualización de marzo de 2023 |
| 2018-2070 | `PobNacionalxÁreaSexoEdad` (`Índice` y `PPED` son documentación) | **Dos filas**: AÑO en la fila 8, nombres por edad (`Hombres 0 años`…) en la fila 9; además columnas Total, Hombres y Mujeres | Actualizado el 18 de julio de 2025 |

- Ambos traen 202 columnas por edad y sexo (2 × 101). Con Área = Total queda una fila por año y la serie 1950-2070 es continua.
- **Puntos de control del PDF (marzo de 2023):** tramo 1950-2017, 14 de 14 coinciden; tramo 2018-2070, 3 de 24. Es lo esperable: el Excel proyectado es una versión posterior (D20).
- **Ruptura del empalme 2017 → 2018 (D25):** crecimiento de 1.26 % (2017) a 1.77 % (2018), 2.09 % y 2.28 %; PSR65 de 7.84 a 7.10; mediana de 30.0 a 29.7. Diferencia de crecimiento frente a 2016-2017: 0.58 puntos porcentuales.
- **ONU frente a DANE en Colombia** (misma fórmula de mediana): población del DANE respecto a la ONU +15.3 % (1950), +8.0 % (1975), +0.1 % (2000), −0.4 % (2023), −3.4 % (2035), −6.3 % (2050), −11.4 % (2070). Año en que el PSR baja de 3.0 (racha de 3 años): 15-64/65+ → ONU 2052, DANE 2058; 15-59/60+ → ONU 2038, DANE 2043. Bajo 2.0 (15-64/65+): ONU 2066, el DANE no cruza antes de 2070.

### 4.10 Geometrías (script 04)

| Chequeo | Resultado |
|---|---|
| Natural Earth 1:50m | 242 filas; 239 polígonos con ISO3 único tras quitar Antártida y disolver `AUS` |
| WPP con polígono | 228 de 237. Sin polígono: Kosovo (`XKX`; Natural Earth usa `KOS`, se recodifica, D22); Réunion, Guadalupe, Martinica, Mayotte y Guayana Francesa (son parte del polígono de Francia en Natural Earth); Gibraltar, Bonaire-San Eustaquio-Saba y Tokelau |
| Polígonos sin contraparte en WPP | ALA, ATF, CYN, HMD, IOT, KAS, KOS (→ XKX), NFK, PCN, SGS, SOL |
| Universo (≥ 1 millón en 2023) | 161 países; con la recodificación de Kosovo los 161 tienen polígono (confirmar al re-ejecutar) |
| Incidente de la primera ejecución | Franja horizontal en el mapa (Rusia), línea fina (Fiji) y punto de Francia en Córcega. Causa probable: `st_make_valid()` con s2 activo. Corrección en D22 |

**Hallazgo posterior (2ª ejecución del 04):** `st_cast(x, "POLYGON")` sobre una geometría de tipo mixto conserva solo la primera parte de cada país; la tabla de control mostró 1 fila por país y áreas de 164 a 27 033 km² (Estados Unidos 185, Indonesia 164, Francia 2 542). Los puntos representativos de los países con varias partes estaban mal, y con ellos los vecinos kNN. Los mapas no se afectan. Corregido con `a_partes()` (D22); **toda cifra de 4.11 queda provisional hasta re-ejecutar**.

### 4.11 Resultados espaciales exploratorios (PROVISIONALES: corrida con puntos defectuosos; ver `ANALISIS_ESPACIAL.md`)

| Variable | 2023 (estimación) | 2050 | 2100 |
|---|---|---|---|
| Moran I, edad mediana | 0.747 | 0.715 | 0.650 |
| Moran I, TFR | 0.718 | 0.700 | 0.640 |
| Moran I, esperanza de vida | 0.671 | 0.679 | 0.669 |

- k = 5, 999 permutaciones. **p = 0.002 es el piso alcanzable**, no un valor estimado. Moran de velocidad de envejecimiento (máxima ganancia por década): 0.327.
- Verificación cruzada: el Moran propio coincide con `spdep::moran.test` (0.7474).
- Serie 1950-2100: la edad mediana pasa de 0.63 (1950) a 0.75 (2023) y baja a 0.65 (2100); el TFR sube de 0.62 a ~0.74 (hacia 2005) y baja a 0.64.
- **Sensibilidad a k (LISA significativos tras FDR, 499 permutaciones):** k = 3 → 0, 0, 0; k = 5 → 72, 54, 29; k = 8 → 83, 87, 80. Con k = 3 el piso de p (0.004) impide que BH declare nada: por eso el script 05 usa ahora 4999 permutaciones en LISA.
- **LISA con k = 5 (alto-alto / bajo-bajo / alto-bajo / bajo-alto / no significativo):** 2023: 35 / 36 / 1 / 0 / 88; 2050: 28 / 35 / 1 / 2 / 94; 2100: 5 / 21 / 1 / 0 / 133; velocidad: 2 / 4 / 1 / 0 / 153.
- **Colombia:** no significativo en todos los mapas (p con FDR: 0.98, 0.62, 0.24 y 0.42). Vecinos más cercanos: Costa Rica, Ecuador, Panamá, Perú y Venezuela.
- Estas cifras son previas a `NSIM_LISA = 4999` y a la recodificación de Kosovo; pueden cambiar levemente.

---

## 5. Registro de decisiones

| # | Decisión | Estado | Evidencia |
|---|---|---|---|
| D1 | Países = `ISO3_code` no nulo (237, incluye Holy See) | ✅ Cerrada | Diferencia 0.0000 % con `World` |
| D2 | Estimación `Time ≤ 2023`; proyección `Time ≥ 2024`, columna `tipo_dato` | ✅ Cerrada | Convención del archivo |
| D3 | Análisis hasta 2100; 2101 solo trae `TPopulation1Jan` | ✅ Cerrada | `diag_final` |
| D4 | Holy See sin suplemento: excluir de análisis con `LE60` o nacimientos por sexo | ✅ Cerrada | `sin_suppl`, `chk_le60_na` |
| D5 | Agregados solo como referencia; nunca sumados con países | ✅ Cerrada | Prueba contra `World` |
| D6 | Sin imputación. `DoublingTime` censurado cuando el crecimiento ≤ 0.5 %; no entra en PCA ni clustering | ✅ Cerrada | Consultas de la sección 6 |
| D7 | Tolerancia de nacimientos = 0.0011 (artefacto de punto flotante) | ✅ Cerrada | `dif_max = 0.001`, 0 fuera de 0.0011 |
| D8 | OtherVariants: países por ISO3, análisis hasta 2100, intervalos con 47 indicadores, `Mean` no sustituye a Medium | ✅ Cerrada | Sección 10 del script 00 |
| D9 | Peso igual por país para arquetipos y análisis espacial; ponderado por población para cifras globales | ✅ Cerrada (plan §3) | `PLAN_ANALITICO.md` |
| D10 | Indicadores de PCA/clustering (sin redundantes, sin `DoublingTime`) | ⏳ Fase 2 | Matriz de correlación |
| D11 | (ver `DECISIONES.md`) | ⏳ Abierta | |
| D12 | Universo de análisis: población ≥ 1 millón en 2023 | ✅ Cerrada | 161 países (scripts 04 y 05) |
| D13 | Regla de fuentes externas: registro previo en `FUENTES.md` | ✅ Cerrada | Plan §5 |
| D14 | Bandas PI: [mínimo, máximo] del par Lower/Upper | ⏳ Confirmar | Colombia 2050: Lower 46.2 > Upper 41.5; revisar `02_orden_bandas_pi.csv` |
| D15 | Transición de arquetipo: ≥ 5 años consecutivos (sensibilidad 3 y 10) | ⏳ Fase 3 | Plan §6.1 |
| D16 | Pronóstico propio "discrepa" solo fuera de la banda del 80 % | ⏳ Fase 3 | Plan §6.2 |
| D17 | Efecto de la migración = Zero migration − Medium | ⏳ Confirmar | Colombia ≈ 0; revisar `02_efecto_migracion.csv` |
| D18 | PSR65 = 15-64/65+ y PSR60 = 15-59/60+; umbrales 4, 3, 2.5, 2; racha de 3 años | ✅ Cerrada | Script 03 |
| D19 | Población por edad de la ONU a 1 de julio | ✅ Cerrada (confirmar `FUENTES.md`) | Suma por edades = `TPopulation1July` en el universo |
| D20 | DANE: 1950-2017 de la versión de marzo de 2023 y 2018-2070 de la actualización de julio de 2025; el PDF valida solo el tramo histórico | ✅ Cerrada | 14/14 y 3/24 puntos de control |
| D21 | Desfase de +1.00 año entre mediana calculada y `MedianAgePop`: ONU y DANE se comparan siempre con la mediana calculada | ✅ Cerrada | Script 03b |
| D22 | Fronteras Natural Earth 1:50m; reparación sin s2 y partición en el antimeridiano; Kosovo `KOS`→`XKX`; área en proyección `cea` | ✅ Cerrada (re-ejecutar) | Franja en Rusia, punto de Francia en Córcega |
| D23 | Pesos kNN con k = 5 (sensibilidad k = 3 y 8), distancia de círculo máximo entre puntos interiores | ✅ Cerrada | Sensibilidad de la sección 4.11 |
| D24 | Inferencia espacial por permutaciones (999 en Moran global, 4999 en LISA), FDR (BH) dentro de cada mapa | ✅ Cerrada | k = 3 sin resultados con 499 permutaciones |
| D25 | Empalme DANE 2017/2018 con ruptura documentada: P3 usa solo 2018-2070 del DANE | ✅ Cerrada | Crecimiento 1.26 % → 1.77 % |

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

**Paquetes de la Fase 1 y de la ampliación espacial:** `readxl` (script 03), `sf`, `rnaturalearth`, `rnaturalearthdata` (04 y 05) y, de forma opcional, `spdep` (verificación cruzada del Moran). `sf` necesita GDAL y PROJ (en Windows vienen con el binario de CRAN).

**Orden de ejecución:** 00 → 01 → 02 → 03b → 03 → 04 → 05 → 06. El 04 debe re-ejecutarse siempre que cambie `RECODIFICAR_NE` o la escala de Natural Earth. El 06 es el más lento (LISA con 4999 permutaciones, también en la sensibilidad a k).

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

**Verificaciones de la ampliación espacial**

| # | Qué verificar | Por qué importa |
|---|---|---|
| V6 | Abrir los PNG de `output/figuras/05_mapa_*.png` (no el panel de RStudio): sin franjas ni líneas horizontales | Era el síntoma de la reparación de geometrías con s2 (D22) |
| V7 | En la salida del 04: punto de Francia dentro de la Francia metropolitana y universo = 161 con polígono | Confirma la recodificación de Kosovo y el cálculo de áreas |
| V8 | Re-ejecutar el 06 y comparar con la sección 4.11 y con `ANALISIS_ESPACIAL.md`: Moran ≈ 0.7 y LISA estable con k = 5 y 8 | Las cifras de 4.11 son previas a las 4999 permutaciones |
| V9 | En el 03: `La suma por edades reproduce la columna Total del Excel` | Validación interna del Excel 2018-2070, independiente del PDF |

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

**Paso 5. Pregunta central.** ✅ Cerrada en `PLAN_ANALITICO.md`: ¿qué tan rápido, y con cuánta incertidumbre, envejecerá Colombia hasta 2100 en comparación con el mundo? Subpreguntas P1 (arquetipos), P2 (incertidumbre y validación) y P3 (soporte).

**Paso 6. Plan analítico previo (ASA B3, C3).** Escribirlo **antes** de analizar:
- Análisis exploratorios y confirmatorios.
- Número de comparaciones y control.
- Indicadores de PCA/clustering (D10): evitar redundancia (no mezclar `LEx`, `LExMale` y `LExFemale`; evitar `Births` junto a `CBR`; excluir `DoublingTime`).
- Ponderación por población (D9).

*Criterio de cierre:* ✅ plan en `PLAN_ANALITICO.md`; D8 y D9 cerradas; D10 se cierra con la matriz de correlación de la Fase 2.

### FASE 1b · Ampliación espacial (scripts 04 y 05) ✅

**Paso E1.** Geometrías y cruce por ISO3 (`04_espacial_geometrias.R`). *Criterio de cierre:* todos los países del universo con polígono; listas de lo que no cruza.
**Paso E2.** Mapas coropléticos (`05_espacial_mapas.R`); Moran global (por año y en años clave), sensibilidad a k y LISA con FDR (`06_espacial_moran_lisa.R`). *Criterio de cierre:* sensibilidad a k reportada y mapas sin artefactos.
**Paso E3.** Ampliaciones pendientes: LISA sobre los arquetipos del clustering (conteo de uniones) y análisis subnacional de Colombia (requiere fuentes nuevas del DANE, por registrar en `FUENTES.md`).

### FASE 2 · EDA (`scripts/07_eda.R`, numeración tentativa)

**Paso 7.** Tendencias globales y regionales, con quiebre estimación/proyección.
**Paso 8.** Transición demográfica: TFR frente a LEx, edad mediana, reemplazo (TFR = 2.1; NRR = 1). Aprovechar el hallazgo de 4.6: la mediana de TFR en 2023 ya está bajo el reemplazo.
**Paso 9.** Correlaciones en un año de referencia, con indicadores no redundantes.
**Paso 10.** Quiebres históricos: caídas anómalas de `LEx` y picos de migración neta (COVID-19, conflictos), listados con año y magnitud.

*Criterio de cierre:* 6-8 figuras finales en `output/figuras/` y lista de hallazgos candidatos.

### FASE 3 · Modelado

**Paso 11.** Características por país (`08_features.R`): niveles en años de referencia, cambios 1950→2023, pendientes recientes. Estandarizar y guardar.
**Paso 12.** PCA (`09_pca_clustering.R`): varianza explicada, cargas e interpretación; supuesto de linealidad.
**Paso 13.** Clustering: k-means y jerárquico; k por silueta, estabilidad por remuestreo y sentido sustantivo; `set.seed(2026)`.
**Paso 14.** Modelos complementarios (`10_modelos_gam_ts.R`): GAM (edf, R² ajustado, AIC, RMSE) y series de tiempo solo si aportan, ajustadas sobre **estimaciones** y contrastadas con la proyección de la ONU.
**Paso 15a.** Perfilar OtherVariants (verificaciones V2-V5) y cerrar D8.
**Paso 15b.** Incertidumbre (`11_incertidumbre_variantes.R`):
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
| B1 Fuentes externas | `FUENTES.md` (E1, E2, E5) con URL, fecha, licencia y transformaciones; versiones del DANE (marzo de 2023 y julio de 2025) declaradas |
| B2 Limitaciones del empalme | Ruptura del DANE en 2017/2018 documentada (D25); el PDF solo valida el tramo histórico (D20) |
| B1/B2 Auditoría de geometrías | Error de `st_cast` documentado y corregido; controles automáticos en 04 y 06; corridas registradas en `ANALISIS_ESPACIAL.md` |
| B3 Comparaciones múltiples | LISA con FDR (BH) dentro de cada mapa; sensibilidad a k y al número de permutaciones (D23, D24) |
| D6 Mapas y grupos | Fronteras ilustrativas; grupos LISA con nombres descriptivos, sin etiquetar países |

---

## 10. Convenciones

- Idioma: comentarios y texto en español; nombres de variables de la ONU sin traducir.
- Objetos en `snake_case`; funciones con verbo (`calcular_amplitud_variantes()`).
- Semilla: `set.seed(2026)`, registrada.
- Estimación frente a proyección siempre visible (línea punteada en 2023/2024 o patrón de color).
- Unidades: población y nacimientos en **miles**; TFR en hijos por mujer; edades en años.
- Nunca sumar países con agregados regionales.
- Mapas en proyección Equal Earth (`+proj=eqearth`), con Colombia resaltada y fronteras declaradas como ilustrativas.
- Operaciones espaciales delicadas (validar, partir, medir áreas) sin s2; distancias entre puntos con s2 (círculo máximo).

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
| Franja horizontal en el mapa (Rusia) y línea fina (Fiji) | `st_make_valid()` con s2 activo reconstruye polígonos que cruzan los 180° | `reparar_geometrias()`: s2 apagado y `st_wrap_dateline()` (D22) |
| Punto representativo de Francia en Córcega | Áreas calculadas con geometrías alteradas | Área en proyección `cea` y comprobación en el script 04 (D22) |
| Kosovo sin polígono | Natural Earth usa `KOS` y WPP usa `XKX` | `RECODIFICAR_NE` (D22) |
| `Selections can't have missing values` en `rename()` | El Excel 1950-2017 no tenía la estructura supuesta | Detección del encabezado en una o dos filas (script 03) |
| Puntos representativos en islas (Francia en Córcega, áreas de 164 km² para Indonesia) | `st_cast(, "POLYGON")` sobre geometría mixta conserva solo la primera parte; el aviso estaba silenciado | `a_partes()` (normaliza a MULTIPOLYGON) y controles de áreas y puntos en el 04 (D22) |
| `read_excel(skip =)` toma el subtítulo como encabezado | `skip` cuenta filas físicas; la lectura sin encabezado recorta las vacías | Leer la hoja completa como texto y localizar AÑO |
| El PDF del DANE no reproduce 2018-2070 | Excel de julio de 2025 frente a PDF de marzo de 2023 | Los puntos de control validan solo el tramo histórico (D20) |
| Salto del DANE entre 2017 y 2018 | Dos versiones empalmadas | D25: P3 usa solo 2018-2070 |
| LISA sin resultados con k = 3 | Pocas permutaciones: el piso de p es demasiado alto para BH | `NSIM_LISA = 4999` (D24) |
| `[FALLA]` de 2.2 % en la suma por edades | Holy See, ~0.5 mil habitantes | Repetir la prueba en el universo (script 03) |

---

## 12. Citación de los datos

United Nations, Department of Economic and Social Affairs, Population Division (2024). *World Population Prospects 2024, Online Edition.* Licencia CC BY 3.0 IGO.

American Statistical Association (2022). *Ethical Guidelines for Statistical Practice.* https://doi.org/10.5281/zenodo.7092386

DANE, Dirección de Censos y Demografía. *Proyecciones de población nacionales por área, sexo y edad (PPED)*: archivo 1950-2017 (actualización de marzo de 2023) y archivo 2018-2070 (actualizado el 18 de julio de 2025). Registrar URL y fecha de descarga en `FUENTES.md`.

Natural Earth. *Admin 0 - Countries*, escala 1:50m, vía los paquetes `rnaturalearth` 1.2.0 y `rnaturalearthdata` 1.0.0 (consultados el 28-oct-2026). Licencia: el proveedor la declara de dominio público; confirmarlo en su sitio antes de citar.