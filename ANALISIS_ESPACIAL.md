# Análisis espacial · bitácora de resultados y observaciones

**Documento vivo.** Registra qué se hizo, qué se encontró y qué sigue en la ampliación espacial (scripts 04, 05 y 06 y `R/utils_espacial.R`). Todo el análisis es **exploratorio** (`PLAN_ANALITICO.md`, sección 7). Última actualización: 2026-10-28.

> **Estado.** La **corrida D** (semillas fijas en LISA y estabilidad Monte Carlo) es la fuente de cifras del reporte. Las corridas A, B y C están reemplazadas (sección 7). Las figuras de las corridas anteriores y de la D se revisaron el 2026-10-29 (sección 5): los mapas no tienen artefactos, pero quedan arreglos de formato (títulos y leyendas cortados, categorías vacías en la leyenda) que se corrigen al re-ejecutar el 05 y el 06.

------------------------------------------------------------------------

## 1. Resumen para el reporte

| \# | Mensaje | Respaldo (corrida C, 161 países) |
|----|----|----|
| 1 | Los países parecidos están cerca unos de otros, y con fuerza | Moran I de la edad mediana = 0.738 en 2023; TFR 0.705; esperanza de vida 0.687. Valor p en su piso (0.002 con 999 permutaciones) |
| 2 | La agrupación se debilita hacia 2100 en edad mediana y fecundidad, no en esperanza de vida | Edad mediana 0.738 → 0.651; TFR 0.705 → 0.612; esperanza de vida 0.687 → 0.680 |
| 3 | En 2023 hay bloques locales claros: 34 países "alto-alto" (los casos listados son europeos) y 37 "bajo-bajo" (los casos listados son africanos) | LISA con k = 5, FDR (BH) 0.05 |
| 4 | El bloque europeo "alto-alto" pierde significancia hacia 2100 | De 34 países en 2023, 29 pasan a "no significativo" en 2100 |
| 5 | Colombia no forma parte de ningún bloque local | "No significativo" en los cuatro análisis (p con FDR entre 0.21 y 0.86) |
| 6 | Sus vecinos envejecerán por encima del promedio mundial, sin llegar a formar un bloque | Rezago estandarizado de Colombia: 0.18 (2023), 0.47 (2050), 0.70 (2100) |
| 7 | La velocidad de envejecimiento casi no se agrupa | Moran I = 0.353; solo 4 de 161 países son significativos |

**Qué no se puede decir todavía:** que la pérdida de agrupación en 2100 sea una dinámica real (puede ser convergencia por construcción del modelo de la ONU); cuántos "clusters" hay exactamente (el conteo depende de k y del azar de las permutaciones: en 2100 con k = 5 va de 37 a 49); nada sobre causas.

## 2. Pregunta, datos y decisiones

**Pregunta.** ¿Los países con envejecimiento, fecundidad y longevidad parecidos están cerca unos de otros, dónde se concentran esos patrones, cambia eso entre la estimación (2023) y la proyección (2050, 2100) y dónde queda Colombia? Es insumo para P1 (arquetipos). No hay análisis subnacional: WPP solo trae países.

| Elemento | Decisión | Referencia |
|----|----|----|
| Universo | Países con ≥ 1 millón de habitantes en 2023: **161** | D12 |
| Variables | Edad mediana (`MedianAgePop`), TFR, esperanza de vida al nacer, y máxima ganancia de edad mediana en una década (2024-2100) | Plan §4 |
| Fronteras | Natural Earth 1:50m; ISO3 con `iso_a3`, `iso_a3_eh` y `adm0_a3`; Kosovo `KOS`→`XKX` | D22 |
| Vecinos | 5 vecinos más cercanos (distancia de círculo máximo entre puntos interiores del polígono más grande); sensibilidad con k = 3 y 8 | D23 |
| Inferencia | Permutaciones bilaterales (999 en Moran global, 199 por año en la serie, 4999 en LISA); FDR (BH) dentro de cada mapa | D24 |

Los vecinos expresan **cercanía**, no frontera común. En la corrida C los de Colombia son Costa Rica, Ecuador, Panamá, Trinidad y Tobago y Venezuela: Perú y Brasil quedan fuera porque sus puntos representativos (dentro de su polígono mayor) están más lejos que Trinidad y Tobago.

## 3. Auditoría de las geometrías

| \# | Hallazgo | Causa | Estado |
|----|----|----|----|
| 1 | Franja horizontal en el mapa (Rusia) y línea fina (Fiji) | Polígonos que cruzan los 180° tras `st_make_valid()` con s2 activo (causa probable) | Corregido con `reparar_geometrias()`; mapas sin artefactos según el equipo |
| 2 | Kosovo sin polígono | Natural Earth usa `KOS`; WPP usa `XKX` | Recodificado; universo 161 de 161 |
| 3 | La tabla de control devolvía 1 fila por país con áreas de 164 a 27 033 km² (EE. UU. 185, Indonesia 164, Francia 2 542); puntos de Francia en Córcega | `st_cast(x, "POLYGON")` sobre una geometría de tipo mixto conserva solo la primera parte; el aviso estaba silenciado. Confirmado por la salida | Corregido con `a_partes()` |
| 4 | El control del antimeridiano "pasaba" sin probar nada | Miraba solo la primera parte de cada país | Corregido |

**Verificación tras la corrección (salida del 04):** 1 512 polígonos individuales para 239 países; partes mayores de Francia 538 333 km², Estados Unidos 7 930 922 km² y Rusia 16 531 210 km²; las dos mayores de Indonesia 528 768 y 428 028 km²; punto de Francia en la metropolitana y de Estados Unidos en el continente; ningún polígono con amplitud ≥ 180° de longitud. La advertencia "st_union assumes that they are planar" al disolver Australia es esperada (s2 apagado a propósito).

## 4. Resultados de la corrida C

### 4.1 Moran global (k = 5, 999 permutaciones)

| Variable | 2023 (estimación) | 2050 (proyección) | 2100 (proyección) |
|----|----|----|----|
| Edad mediana | 0.738 | 0.707 | 0.651 |
| TFR | 0.705 | 0.685 | 0.612 |
| Esperanza de vida al nacer | 0.687 | 0.690 | 0.680 |

Velocidad de envejecimiento (máxima ganancia por década): I = 0.353. Valor esperado bajo aleatoriedad: −0.006. Todos con p = 0.002, que es el **piso** con 999 permutaciones, no un valor estimado. El Moran propio coincide con `spdep::moran.test` (0.7379).

### 4.2 Serie 1950-2100 (199 permutaciones por año)

| Año  | Edad mediana | TFR   | Esperanza de vida |
|------|--------------|-------|-------------------|
| 1950 | 0.685        | 0.627 | 0.539             |
| 1975 | 0.721        | 0.662 | 0.534             |
| 2000 | 0.712        | 0.695 | 0.778             |
| 2023 | 0.738        | 0.705 | 0.687             |
| 2050 | 0.707        | 0.685 | 0.690             |
| 2075 | 0.658        | 0.655 | 0.685             |
| 2100 | 0.651        | 0.612 | 0.680             |

La esperanza de vida salta de 0.534 (1975) a 0.778 (2000) y vuelve a \~0.69: es el movimiento más llamativo de la serie y se discute en la sección 6.

### 4.3 Sensibilidad al número de vecinos (edad mediana; semilla fija)

| k   | Moran I 2023 / 2050 / 2100 | LISA significativos 2023 / 2050 / 2100 |
|-----|----------------------------|----------------------------------------|
| 3   | 0.757 / 0.719 / 0.666      | **0 / 0 / 0**                          |
| 5   | 0.738 / 0.707 / 0.651      | 72 / 62 / 42                           |
| 8   | 0.732 / 0.707 / 0.653      | 83 / 82 / 83                           |

El Moran global casi no depende de k. **El conteo LISA sí.** Con k = 3 no sale nada significativo ni con 4 999 permutaciones: no es el piso del valor p (aquí vale 0.0004), sino falta de potencia, porque el promedio de solo tres vecinos varía demasiado al permutar y BH sobre 161 pruebas exige valores p muy pequeños. Con k = 8 el conteo es estable entre años (82-83); con k = 5 baja de 72 a 42.

### 4.4 LISA de la edad mediana (k = 5, 4 999 permutaciones, semilla 2026, FDR-BH 0.05)

| Variable | Año | Alto-Alto | Bajo-Bajo | Alto-Bajo | Bajo-Alto | No significativo |
|----|----|----|----|----|----|----|
| Edad mediana | 2023 | 34 | 37 | 1 | 0 | 89 |
| Edad mediana | 2050 | 25 | 36 | 1 | 0 | 99 |
| Edad mediana | 2100 | 9 | 31 | 1 | 1 | 119 |
| Velocidad (máx. ganancia por década) | — | 0 | 2 | 1 | 1 | 157 |

**Estabilidad Monte Carlo del conteo** (k = 5, semillas 2027 a 2029): 2023 → 72 a 73; 2050 → 61 a 62; 2100 → **37 a 49** (la semilla 2026 da 42). El conteo de 2100 se reporta como rango. Los valores de 2023 y 2050 son prácticamente fijos.

### 4.5 Transiciones del grupo LISA, 2023 → 2100 (países)

| 2023  2100       | Alto-Alto | Bajo-Bajo | Alto-Bajo | Bajo-Alto | No significativo |
|------------------|-----------|-----------|-----------|-----------|------------------|
| Alto-Alto        | 5         | 0         | 0         | 0         | **29**           |
| Bajo-Bajo        | 0         | 26        | 0         | 0         | 11               |
| Alto-Bajo        | 0         | 0         | 1         | 0         | 0                |
| No significativo | 4         | 5         | 0         | 1         | 79               |

-   **Europa deja de ser un bloque.** Los 29 casos "alto-alto" → "no significativo" son europeos: Albania, Austria, Bélgica, Croacia, Chequia, Dinamarca, Estonia, Finlandia, Francia, Alemania, Hungría, Irlanda, Italia, Kosovo, Letonia, Lituania, Países Bajos, Macedonia del Norte, Noruega, Polonia, Moldavia, Rumanía, Eslovaquia, Eslovenia, España, Suecia, Suiza, Ucrania y Reino Unido.
-   **El bloque africano es mayormente persistente.** 26 de 37 "bajo-bajo" siguen siéndolo en 2100. Los 11 que dejan de serlo: Etiopía, Guinea-Bisáu, Kenia, Mauritania, Mozambique, Senegal, Somalia, Sudán del Sur, Sudán, Tanzania y Zimbabue.
-   **Los países de borde cambian con la semilla.** Entre la corrida C y la D, Bosnia y Herzegovina salió de la lista europea y entraron Albania, Kosovo y Macedonia del Norte; Etiopía, Guinea-Bisáu, Kenia, Senegal y Sudán entraron en la lista africana. Los nombres cercanos al umbral (Balcanes y Cuerno de África) no son estables; el bloque europeo y el africano en conjunto sí.
-   **Aparecen bloques nuevos:** 4 países pasan a "alto-alto" y 5 a "bajo-bajo" (lista en `output/tablas/06_lisa_resultados.csv`).
-   **Lectura relativa.** LISA mide el contraste con la media mundial de cada año. Cuando el mundo envejece, el contraste de Europa se reduce aunque su edad mediana siga siendo alta.

### 4.6 Colombia

| Análisis                    | Valor | Rezago (z) | p     | p con FDR | Grupo            |
|-----------------------------|-------|------------|-------|-----------|------------------|
| Edad mediana 2023           | 31.6  | 0.18       | 0.686 | 0.855     | No significativo |
| Edad mediana 2050           | 43.7  | 0.47       | 0.309 | 0.465     | No significativo |
| Edad mediana 2100           | 51.8  | 0.70       | 0.110 | 0.206     | No significativo |
| Velocidad de envejecimiento | 4.7   | 0.81       | 0.076 | 0.290     | No significativo |

El rezago creciente indica que el promedio de sus vecinos más cercanos queda cada vez más por encima del promedio mundial. Ni Colombia ni su entorno llegan a ser significativos al corregir por 161 pruebas. Vecinos más cercanos: Costa Rica, Ecuador, Panamá, Trinidad y Tobago y Venezuela.

## 5. Figuras: revisión del 2026-10-29

| Figura | Qué muestra | Observaciones |
|----|----|----|
| `05_mapa_edad_mediana`, `05_mapa_tfr` | Edad mediana y TFR en 2023, 2050 y 2100 | Sin franjas ni artefactos; Colombia resaltada. **Título largo y barra de leyenda cortados por la derecha** |
| `05_mapa_velocidad_envejecimiento` | Máxima ganancia de edad mediana en una década | China tiene los valores más altos; Europa occidental, Norteamérica y África subsahariana, los más bajos. Barra de leyenda ajustada al borde |
| `05_mapa_anio_maximo_velocidad` | Año del máximo | América y Asia occidental alcanzan su máximo antes de 2050 (tonos oscuros); África subsahariana y Asia central, hacia 2070-2090. Colombia, en tonos oscuros (2037 según la tabla) |
| `06_moran_dispersion` | Dispersión de Moran en 2023, 2050 y 2100 | Los grupos se ven como nubes separadas (Europa arriba a la derecha; África abajo a la izquierda). Colombia queda cerca del centro en 2023 y desplazada hacia arriba y a la derecha en 2100, pero dentro de la nube no significativa |
| `06_moran_serie_temporal` | Moran 1950-2100, tres variables | La edad mediana y el TFR son curvas suaves. **La esperanza de vida es muy irregular antes de 2025**: \~0.5 hacia 1975, máximo cercano a 0.78 hacia 2000, y hundimientos hacia 2010 y 2021 |
| `06_mapa_lisa_edad_mediana` | Grupos LISA en tres años | Alto-alto en Europa y Asia oriental; bajo-bajo en África subsahariana. En 2100 aparece un bloque bajo-bajo en la península arábiga. **La Guayana Francesa sale con el color de Francia** (artefacto de Natural Earth). La leyenda no dibuja el cuadro de las categorías vacías |
| `06_mapa_lisa_velocidad` | Grupos LISA de la velocidad | Solo señales aisladas (Europa noroccidental y la península de Corea); ningún bloque grande |

**Correcciones de formato ya hechas en el código (efectivas al re-ejecutar):** barra de leyenda de 2.2 cm por clave y títulos de mapas más cortos y de menor tamaño (`tema_mapa()`, script 05); pie de figura de los mapas LISA en tres líneas con aviso sobre la Guayana Francesa; paleta de control con etiquetas debajo de los colores (`tema.R`).

**Pendiente de formato:** las categorías vacías no dibujan su cuadro en la leyenda de los mapas LISA (cosmético).

## 6. Observaciones

**Robustas** (se mantienen en las cuatro corridas):

1.  La autocorrelación positiva y fuerte (0.53 a 0.78) aparece en las tres variables y en todo el periodo.
2.  La edad mediana y el TFR pierden agrupación entre 2023 y 2100 (−0.09 en ambas en la corrida D; −0.10 y −0.08 en A; −0.05 y −0.06 en B). El signo es el mismo en las cuatro; la magnitud varía.
3.  Colombia nunca queda en un bloque significativo.
4.  Los dos bloques mayores (Europa alto-alto y África bajo-bajo) existen en 2023 y 2050 con conteos casi fijos entre semillas.

**Dependen de decisiones o del azar:**

-   El número de países significativos en LISA: depende de k (0 con k = 3; 72 con k = 5; 83 con k = 8 en 2023) y, en 2100, del azar de las permutaciones (37 a 49).
-   La pertenencia de los países de borde a un bloque (Balcanes, Cuerno de África).
-   Los puntos representativos: entre las corridas A, B y C el Moran de una misma variable y año varió hasta 0.06. Diferencias de Moran menores a \~0.03 no deben interpretarse.

**Hipótesis sin verificar** (no afirmar en el reporte sin pruebas):

-   El Moran de \~0.7 refleja sobre todo gradientes continentales (África joven; Europa y Asia oriental envejecidas), no vecindades locales.
-   La irregularidad del Moran de la esperanza de vida (picos y hundimientos hacia 1975, 2000, 2010 y 2021) podría deberse a choques puntuales de mortalidad en algunos países (conflictos, VIH/sida, el terremoto de Haití de 2010, la COVID-19) que rompen o refuerzan la similitud regional. El script 07 lista las mayores caídas de la esperanza de vida para contrastarlo.
-   La pérdida de agrupación en 2100 podría ser convergencia de los supuestos de fecundidad y mortalidad de la ONU y no una dinámica regional real; los modelos de la ONU probablemente comparten información entre países.
-   Que Trinidad y Tobago aparezca entre los vecinos de Colombia es un efecto de usar un punto por país; con otra definición de vecindad podría cambiar.

## 7. Registro de corridas

### Corrida A (primera; 160 países; puntos defectuosos) — reemplazada

Moran de la edad mediana 0.747 / 0.715 / 0.650; TFR 0.718 / 0.700 / 0.640; esperanza de vida 0.671 / 0.679 / 0.669; velocidad 0.327. LISA k = 5 (999 permutaciones): 72 / 54 / 29 significativos.

### Corrida B (161 países; puntos aún defectuosos) — reemplazada

Moran de la edad mediana 0.720 / 0.713 / 0.670; TFR 0.690 / 0.676 / 0.626; esperanza de vida 0.631 / 0.639 / 0.632; velocidad 0.300. LISA k = 5 (4 999 permutaciones): 71 / 66 / 26 significativos.

### Corrida C (puntos válidos; sin semilla por llamada) — reemplazada

Los Moran son los de la corrida D. LISA k = 5: 72 / 62 / 35 en la tabla de sensibilidad y 72 / 61 / 48 en la corrida principal (mismas entradas, otras permutaciones): evidencia del ruido Monte Carlo en 2100.

### Corrida D (semilla fija por llamada; estabilidad Monte Carlo) — vigente

Secciones 4.1 a 4.6. Fecha: 2026-10-29. Semilla 2026 (y 2027 a 2029 en la prueba de estabilidad). Permutaciones: 999 (Moran global), 199 (serie), 4 999 (LISA). Los Moran globales de 4.1 y 4.2 son idénticos a los de la corrida C (misma semilla de partida y mismo código).

## 8. Limitaciones

-   Unidad de análisis: país. Los resultados dependen del tamaño y la forma de las fronteras (problema de la unidad de área modificable); un país como Rusia o Estados Unidos se resume en un solo punto.
-   Cercanía no es frontera: la matriz kNN mezcla vecinos contiguos y vecinos al otro lado del mar, y excluye vecinos contiguos grandes (Brasil) cuando su punto queda lejos.
-   2023 es estimación; 2050 y 2100 son proyecciones de la variante Medium, no observaciones.
-   BH se aplica dentro de cada mapa, no entre mapas; el análisis completo incluye cientos de pruebas locales.
-   Los territorios pequeños quedan fuera de Moran/LISA, aunque aparecen en los mapas.
-   LISA es relativo a la media mundial de cada año.
-   Los grupos describen patrones; no son etiquetas sobre los países (principio D6 de la ASA).

## 9. Pendientes

-   [ ] Re-ejecutar 05 y 06 para aplicar las correcciones de formato (títulos, leyendas, pie de figura) y revisar los PNG resultantes.
-   [ ] Contrastar la hipótesis de la esperanza de vida con las mayores caídas por país-año del script 07.
-   [ ] Vecindad alternativa (banda de distancia) y otro punto representativo (centroide frente a punto interior) para medir la sensibilidad.
-   [ ] Moran dentro de grandes regiones, para separar gradiente continental de agrupación local.
-   [ ] Identificar con nombre los 4 y 5 países que pasan a "alto-alto" y "bajo-bajo" en 2100.
-   [ ] Cuadro de leyenda para las categorías LISA vacías (cosmético).
-   [ ] LISA o conteo de uniones sobre los arquetipos del clustering, cuando exista (Fase 3).
-   [ ] Análisis subnacional de Colombia: requiere proyecciones departamentales y fronteras del DANE; fuentes nuevas por registrar en `FUENTES.md` antes de usarlas.

## 10. Reproducibilidad

``` text
scripts/04_espacial_geometrias.R   fronteras, cruce ISO3, puntos representativos
scripts/05_espacial_mapas.R        mapas coropléticos
scripts/06_espacial_moran_lisa.R   Moran, LISA, sensibilidad, estabilidad, figuras y resumen .md
R/utils_espacial.R                 kNN, Moran, LISA, a_partes(), reparar_geometrias(), mapas
```

Semilla: `set.seed(2026)`. Paquetes: `sf`, `rnaturalearth` 1.2.0, `rnaturalearthdata` 1.0.0, `spdep` (opcional, verificación cruzada). Tablas en `output/tablas/06_*.csv`; figuras en `output/figuras/05_*.png` y `06_*.png`.
