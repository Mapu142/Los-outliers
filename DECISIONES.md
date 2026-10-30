---
editor_options: 
  markdown: 
    wrap: sentence
---

# Registro de decisiones · ASA DataQuest 2026 (WPP 2024)

Este documento es la **única fuente de verdad** sobre cómo se tratan los datos.
Cada decisión se toma una vez, se justifica con evidencia reproducible y todo el código posterior la hereda.
Si una decisión cambia, **no se borra**: se marca como *Reemplazada* y se agrega una nueva con su fecha.

Vínculo con las guías de la ASA (2022): este registro cumple B1 (comunicar fuentes, procesamiento y manejo de faltantes), B2 (transparencia en supuestos) y F4 (reproducibilidad).

**Fecha de la Fase 0:** 2026-10-20 · **Última actualización:** 2026-10-28 · **Scripts de evidencia:** `scripts/00` a `scripts/06` · **Parámetros:** `R/config.R`

> **Nota de la revisión del 2026-10-28.** Se unificó este archivo: se quitaron duplicados de D15-D18 y D19-D20 y se corrigió el formato de D19-D25.
> **Renumeración:** la versión previa tenía dos decisiones con el mismo número que otras ya usadas por el código y el README.
> La propuesta "COVID-19 en la validación" (antes D21) pasa a **D26**, y la propuesta de limitar la comparación ONU-DANE (antes llamada D22 en el texto de resultados del script 03) pasa a **D27**.

------------------------------------------------------------------------

## Resumen

| \# | Decisión | Estado |
|----|----|----|
| D1 | País = `ISO3_code` no nulo | ✅ Cerrada |
| D2 | Estimación ≤ 2023; proyección ≥ 2024 | ✅ Cerrada |
| D3 | Análisis hasta 2100 | ✅ Cerrada |
| D4 | Holy See sin suplemento | ✅ Cerrada |
| D5 | Agregados solo como referencia | ✅ Cerrada |
| D6 | Sin imputación; `DoublingTime` censurado | ✅ Cerrada |
| D7 | Tolerancia de nacimientos 0.0011 | ✅ Cerrada |
| D8 | Cobertura de OtherVariants | ✅ Cerrada |
| D9 | Peso igual por país (arquetipos y espacial); ponderado por población (cifras globales) | ✅ Cerrada |
| D10 | Indicadores del PCA y clustering | ⏳ Se cierra en la Fase 2 |
| D11 | Idioma del reporte final | ⏳ Abierta |
| D12 | Universo: población ≥ 1 millón en 2023 (161 países) | ✅ Cerrada |
| D13 | Regla de fuentes externas | ✅ Cerrada |
| D14 | Bandas PI como [mínimo, máximo] | ✅ Cerrada (evidencia del script 02) |
| D15 | Transición de arquetipo: ≥ 5 años consecutivos | ⏳ Fase 3 |
| D16 | Validación de pronósticos y "discrepa" fuera de la banda del 80 % | ⏳ Fase 3 |
| D17 | Efecto de la migración con *Zero migration* | ⏳ Confirmar con todo el universo |
| D18 | PSR65 y PSR60; umbrales 4, 3, 2.5 y 2; racha de 3 años | ✅ Cerrada |
| D19 | Población por edad de la ONU a 1 de julio | ✅ Cerrada |
| D20 | DANE: versiones, filtro Área = Total y alcance de los puntos de control | ✅ Cerrada |
| D21 | Desfase de +1 año en la mediana | ✅ Cerrada |
| D22 | Geometrías: fronteras, reparación, `a_partes()` y recodificaciones | ✅ Cerrada (corrida C) |
| D23 | Pesos espaciales kNN, k = 5 | ✅ Cerrada |
| D24 | Inferencia espacial: permutaciones, semillas y FDR | ✅ Cerrada |
| D25 | Empalme del DANE en 2017/2018 | ✅ Cerrada |
| D26 | COVID-19 en la validación (antes D21) | 🟡 Propuesta |
| D27 | Comparación ONU-DANE solo en 2000-2070 (antes "D22" del script 03) | 🟡 Propuesta |

------------------------------------------------------------------------

## Fase 0 · D1-D8 (cerradas)

### D1 · Definición de país

**Decisión.** Un registro es un país o área si y solo si `ISO3_code` no es nulo ni vacío.
No se usa `LocTypeName` para filtrar.

**Justificación.** El campo `Location` mezcla países con agregados regionales, de ingreso y grupos ad hoc.
Sumar sin filtrar duplica la población.
`LocTypeName` no sirve como filtro porque 234 ubicaciones lo tienen en `NA`.

**Alternativas descartadas.**

-   Filtrar por `LocTypeName = 'Country/Area'`: coincide hoy con ISO3 (237), pero depende de un campo que la guía advierte como inconsistente.
-   Filtrar por lista manual de nombres: frágil y no reproducible.

**Evidencia.**

-   237 ubicaciones con ISO3 + 318 agregados = 555 ubicaciones.
-   Suma de `TPopulation1July` de los 237 países frente a la fila `World`: diferencia máxima de **0.0000 %** en 1950-2100.
-   Los 237 de `Country/Area` tienen ISO3; las otras categorías tienen 0.

**Impacto.** Todo análisis a nivel país parte de `medium_paises`.
Incluye Holy See (237 y no 236).

**Implementación.** `SQL_ES_PAIS` en `R/utils_datos.R`; secciones 3 y 4 del script 00.

### D2 · Estimación frente a proyección

**Decisión.** Los años hasta 2023 (`CFG$ultimo_anio_estimado`) son estimaciones; desde 2024 son proyección de la variante Medium.
Toda tabla analítica lleva la columna `tipo_dato`.

**Justificación.** La documentación de la ONU y del concurso lo establece así.
Mezclar ambas como si fueran observaciones sesga las conclusiones, y la proyección es un escenario, no un hecho.

**Alternativas descartadas.** Tratar la serie como continua sin marca.

**Evidencia.** OtherVariants comienza en 2024 y solo contiene proyecciones, lo que es consistente con el corte.

**Impacto.** Los gráficos muestran el corte con una zona sombreada y línea punteada (`capa_proyeccion()` en `R/tema.R`).
Los modelos se ajustan sobre estimaciones y la proyección se usa como contraste.

### D3 · Año final del análisis

**Decisión.** El análisis llega hasta **2100** (`CFG$ultimo_anio_analisis`).
El año 2101 solo se usaría para `TPopulation1Jan`.

**Justificación.** En 2101 las 237 filas de países traen únicamente `TPopulation1Jan`; los otros 53 indicadores están vacíos.
`TPopulation1Jan` de 2101 equivale al cierre de 2100.
Incluir 2101 introduciría faltantes artificiales en modelos, clusters y gráficos.

**Alternativas descartadas.** Mantener 2101 y tratarlo como faltante: contamina el conteo de `NA` y complica cada modelo.

**Evidencia.**

-   Indicadores con datos en 2101 (todos los 54 evaluados): solo `TPopulation1Jan` (237 filas).
-   2099 y 2100: 237 de 237 filas completas en `TPopulation1July`, `TFR`, `LEx` y `Births`.
-   La comparación con `World` da `NA` únicamente en 2101.
-   El suplemento también termina en 2100.

**Impacto.** La tabla maestra tiene 237 × 151 = **35,787 filas**.
Medium y suplemento cubren los mismos años.

### D4 · Holy See y el suplemento

**Decisión.** Holy See (`VAT`, LocID 336) no tiene filas en el suplemento.
Se excluye de cualquier análisis que use `BirthsMale`, `BirthsFemale`, `LE60`, `LE60Male` o `LE60Female`.
En los demás análisis permanece.

**Justificación.** La documentación del suplemento lo indica: Holy See aparece en Medium pero no estaba en las descargas del portal.
No se imputa, porque no hay una base razonable para ello.

**Alternativas descartadas.** Imputar con la media regional (sin sustento); eliminar Holy See de todo el proyecto (pérdida innecesaria de información).

**Evidencia.**

-   Países de Medium sin filas en el suplemento: únicamente Holy See.
-   Tras el `LEFT JOIN`, `LE60` es `NULL` solo para Holy See, en **151 filas** (1950-2100).

**Impacto.** Los análisis con suplemento usan 236 países; el resto, 237.
Debe indicarse en cada figura o tabla donde aplique.

### D5 · Agregados regionales

**Decisión.** Las 318 filas de agregados (regiones, grupos de ingreso, mundo, etc.) se usan solo como referencia de contraste y para validar totales.
Nunca se suman ni se promedian junto con países.

**Justificación.** Cada agregado ya contiene a los países que lo componen; combinarlos duplica el peso de esos países.

**Evidencia.** Vista `medium_agregados`; la fila `World` se usa como control de la suma de países (D1).

**Impacto.** El reporte y la app distinguen explícitamente "país" de "agregado".

### D6 · Faltantes y `DoublingTime`

**Decisión.** No se imputa ningún valor.
`DoublingTime` presenta **censura estructural** y se trata así:

-   No entra en PCA, clustering ni modelos.
-   Su información útil está contenida en `PopGrowthRate`.
-   En gráficos descriptivos se muestra solo donde existe, con una nota explícita.

**Justificación.** Tras recortar a 2100, **52 de 54 indicadores están completos** para los 237 países.
`DoublingTime` es el único con `NA` (15,938 filas, 44.5 %), y esos `NA` no son aleatorios: el indicador no existe cuando el crecimiento anual es ≤ 0.5 %.
Una población que no crece (o crece muy poco) no tiene un tiempo de duplicación razonable.
Imputarlo inventaría valores inexistentes y usar solo las filas completas sesgaría la muestra hacia países en crecimiento.

**Alternativas descartadas.**

-   Imputar con un valor muy alto o con la media: crea datos que no existen.
-   Eliminar las filas con `NA`: elimina casi la mitad de los registros y sesga hacia países en crecimiento.
-   Calcular `DoublingTime` propio: sustituiría la definición de la ONU sin necesidad.

**Evidencia.**

| Condición                            | Filas  | `DoublingTime = NA` |
|--------------------------------------|--------|---------------------|
| Crecimiento ≤ 0 (en `medium_paises`) | 10,604 | 10,604 (100 %)      |
| Crecimiento \> 0 y ≤ 0.5             | 5,334  | 5,334 (100 %)       |
| Crecimiento \> 0.5                   | —      | 0                   |

-   Estimación: `NA` con crecimiento de 0.001 a 0.500; con dato, de 0.501 a 37.9.
-   Proyección: `NA` con crecimiento de 0.001 a 0.500; con dato, de 0.501 a 4.41.
-   Los rangos no se solapan en ninguno de los dos periodos (a la precisión de 4 decimales de esa consulta). El script 00 (sección 9) reporta el umbral exacto sin redondeo.

**Impacto.** `CFG$umbral_doubling = 0.5`.
No hay imputación en ninguna parte del proyecto.

### D7 · Tolerancia de nacimientos por sexo

**Decisión.** La tolerancia para verificar `BirthsMale + BirthsFemale = Births` es **0.0011** (`CFG$tol_births`).

**Justificación.** El suplemento documenta una coincidencia "dentro de 0.001".
Con ese umbral exacto, el punto flotante marca como violación a filas cuya diferencia es exactamente 0.001.
No es una inconsistencia de los datos.

**Alternativas descartadas.** Mantener 0.001 y tratar las filas marcadas como errores del suplemento (diagnóstico incorrecto).

**Evidencia.**

-   Con tolerancia 0.001: 4,852 de 35,636 filas (13.6 %) fuera de tolerancia.
-   Diferencia máxima observada: **0.001**.
-   Con tolerancia 0.0011: **0** filas fuera.

**Impacto.** El suplemento es coherente con `Births`.
Para tasas por sexo con pocos nacimientos, usar `SRB` de Medium, como indica su documentación.

### D8 · Cobertura de OtherVariants

**Decisión.** Para el análisis de incertidumbre (Paso 15):

-   Los países se filtran por `ISO3_code`, igual que en Medium (D1).
-   El análisis llega hasta **2100**: en todas las variantes, el año 2101 solo trae `TPopulation1Jan` (D3).
-   Los **intervalos** (Lower/Upper 80 PI, Lower/Upper 95 PI, Median PI) se usan solo para los 47 indicadores que traen.
-   **`Mean` no sustituye a `Medium`**: solo trae `TFR`, `LExMale` y `LExFemale`.
-   `Constant mortality` se usa solo para los 30 indicadores que trae.

**Justificación.** Las variantes no son homogéneas: no todas reportan los mismos indicadores ni las mismas ubicaciones.
Asumir lo contrario produciría comparaciones con huecos silenciosos.

**Alternativas descartadas.** Usar `Mean` como proxy de Medium (no coincide); incluir 2101 (incompleto).

**Evidencia.**

| Hecho | Resultado |
|----|----|
| Países por variante | 237 en las 18 variantes |
| Escenarios (11 de 12) | 54 indicadores con datos |
| `Constant mortality` | 30 indicadores con datos |
| Intervalos PI | 321 ubicaciones = 237 países + 84 agregados; 47 indicadores |
| Indicadores ausentes en PI | `NRR`, `SRB`, `DeathsMale`, `DeathsFemale`, `InfantDeaths`, `LBsurvivingAge1`, `Under5Deaths` |
| `Mean` | 237 países, 2024-2100; solo `TFR`, `LExMale`, `LExFemale` |
| `Mean` frente a `Medium` | Diferencia absoluta máxima en `TFR`: 0.274 (no son equivalentes) |
| 2101 en todas las variantes | Solo `TPopulation1Jan` |

**Impacto.** Las medidas de incertidumbre se construyen sobre `TPopulation1July`, `TFR` y `LEx`, presentes en High, Low y los intervalos.
Los indicadores ausentes de los intervalos no tendrán banda de incertidumbre y se dirá explícitamente.

------------------------------------------------------------------------

## Fase 1 · D9-D18 (plan analítico y scripts 01 y 02)

### D9 · Ponderación

**Decisión.** Peso igual por país para tipologías, clustering y análisis espacial (la unidad de interés es el país); ponderado por población para cifras globales y comparaciones de carga demográfica mundial.
**Justificación.** Las medianas sin ponderar (p. ej. TFR mediano 2023 = 1.95) responden a "¿cómo es el país típico?", no a "¿cómo vive la gente?".
Son preguntas distintas y deben rotularse.
**Alternativa descartada.** Ponderar todo por población (los países pequeños desaparecerían de los arquetipos).
**Estado.** Aplicada en los scripts 04 a 06.

### D10 · Indicadores del PCA y clustering

**Propuesta.** Candidatos: `TFR`, `LE60` (o `LEx`), `MedianAgePop`, índice vital (`Births/Deaths`, en logaritmo) y ganancia de edad mediana a 10 años.
Excluir `DoublingTime` (D6) y evitar versiones por sexo del mismo indicador.
**Cierre.** Tras la matriz de correlación de la Fase 2.

### D12 · Universo de análisis

**Decisión.** Descriptivo con los 237 países y áreas; clustering, rankings y autocorrelación espacial solo con países de 1 millón de habitantes o más en 2023.
**Evidencia.**

-   Sin umbral, los diez primeros puestos de velocidad de envejecimiento son territorios pequeños (Saint Martin 11.4 años por década en 2027, Cook Islands, Maldivas…); Colombia no aparece.
-   Con el umbral quedan **161 países** y se excluyen 76, que suman el **0.21 %** de la población mundial (script 02). Los 161 tienen polígono (script 04).
-   Dentro del universo, Colombia ocupa el puesto **22** en velocidad de envejecimiento (4.7 años por década; el máximo anual cae en 2037 y, mirando solo años múltiplos de diez, en 2040). Encabezan Puerto Rico, Hong Kong, Taiwán, Singapur y Corea.

**Alternativa descartada.** Sin umbral (los territorios pequeños dominan los rankings).

### D13 · Datos externos

**Decisión.** Confirmado por el equipo: el concurso incentiva complementar con otras fuentes.
Toda fuente se registra en `data/raw/externos/FUENTES.md` (URL, fecha, licencia, transformaciones) antes de usarse.
Unión por `ISO3_code`; países sin correspondencia, listados.
Ninguna fuente externa sustituye a Medium en la comparación principal.

### D14 · Banda oficial de incertidumbre

**Decisión.** La banda se construye como [mínimo, máximo] del par Lower/Upper de cada nivel (80 % y 95 %).
**Evidencia (script 02).** Proporción de países donde "Lower 80 PI" es numéricamente menor que "Upper 80 PI":

| Indicador      | 2050      | 2100      |
|----------------|-----------|-----------|
| `TFR`          | 1.000     | 1.000     |
| `LEx`          | 1.000     | 1.000     |
| `MedianAgePop` | **0.034** | **0.063** |

Las etiquetas siguen el orden normal en fecundidad y esperanza de vida, pero están **invertidas** en la edad mediana (menos fecundidad implica población más envejecida).
En Colombia, "Lower 80 PI" da mayor edad mediana que "Upper 80 PI" (46.2 frente a 41.5 en 2050; 59.6 frente a 47.2 en 2100).
Además, `Medium` cae dentro de la banda del 80 % en el **96.0 %** de los país-año (n = 18,249); el 4 % restante se revisará, porque `Medium` es una proyección determinística y no la mediana probabilística.
**Alternativa descartada.** Asumir que "Lower" es numéricamente menor.

### D15 · Regla de transición de grupo

**Propuesta.** Un país pasa al grupo B en el primer año desde el cual permanece en B al menos 5 años consecutivos.
Sensibilidad con 3 y 10.
Se reporta con rango.
**Alternativa descartada.** Primer año en B (sensible a oscilaciones).

### D16 · Validación del pronóstico y discrepancia con la ONU

**Propuesta.** Ventana móvil dentro de 1950-2023 con horizontes de 5, 10 y 20 años, contra líneas base ingenua y de deriva.
Un pronóstico propio "discrepa" de la ONU solo si cae fuera de la banda del 80 % oficial.
La extrapolación a 2100 es ilustrativa.
**Evidencia.** Hay 74 años de historia por país frente a 77 años a proyectar (relación 1.04); no se puede validar un horizonte de 77 años.
Incertidumbre oficial de referencia (Colombia, edad mediana): ancho del 80 % de 4.7 años (2050) y 12.4 años (2100); del 95 %, 7.6 y 21.9.

### D17 · Migración

**Decisión.** No se excluye de las variables; se cuantifica como *Zero migration* − *Medium* sobre la edad mediana, en todo el universo.
**Evidencia parcial.** Colombia: 43.7 frente a 43.9 en 2050; 51.8 frente a 51.8 en 2100 (efecto casi nulo).
**Pendiente.** Confirmar el efecto en todo el universo con `output/tablas/02_efecto_migracion.csv`.
**Alternativa descartada.** Excluir las variables afectadas por migración.

### D18 · Soporte demográfico

**Decisión.** Se calculan PSR65 (población 15-64 / 65+, definición internacional) y PSR60 (15-59 / 60+, la que usa el DANE en sus indicadores de estructura).
Umbrales de referencia 4, 3, 2.5 y 2 como escenarios, no estándares.
Año de cruce: primer año con PSR bajo el umbral durante 3 años seguidos.
Las edades de jubilación vigentes en Colombia (57 mujeres y 62 hombres, según prensa; confirmar con fuente oficial) quedan entre ambas definiciones, por lo que se reportan las dos y se usa la diferencia como medida de sensibilidad.
**Límite.** El PSR no mide sostenibilidad fiscal de un sistema pensional.
**Alternativa descartada.** Un solo umbral o un solo año de cruce sin racha.

------------------------------------------------------------------------

## Fase 1 · D19-D25 (estructura por edad, DANE y ampliación espacial)

### D19 · Población por edad de la ONU a 1 de julio

-   **Fecha:** 2026-10-28.
-   **Decisión:** el script 03 usa la población por edad simple a 1 de julio (la ONU entrega 1 de enero y 1 de julio). Una sola fecha para toda la serie.
-   **Razón:** `TPopulation1July` y `MedianAgePop` son de 1 de julio, y el DANE publica a 30 de junio. Mezclar julio (1950-2023) con enero (2024-2100) introduce un desfase de medio año en el empalme.
-   **Evidencia:** los cuatro archivos de la ONU estaban completos (237 países, 1950-2100, edades 0-100, 3,614,487 filas). La suma por edades reproduce `TPopulation1July`; en el universo la diferencia relativa máxima es 1.5e-5 (17 personas). El máximo global de 2.2 % corresponde a Holy See.
-   **Alternativa descartada:** base de 1 de enero (no es comparable con las demás columnas ni con el DANE).
-   **Pendiente:** confirmar que `FUENTES.md` registra los archivos de 1 de julio.

### D20 · DANE como fuente secundaria: versiones y puntos de control

-   **Fecha:** 2026-10-28.
-   **Decisión:** se usa la serie nacional por edad simple en dos archivos: 1950-2017 (actualización de marzo de 2023) y 2018-2070 (actualizado el 18 de julio de 2025). Se filtra a Área Geográfica = Total (sin ese filtro la población se triplica: Cabecera + Rural + Total). El PDF de marzo de 2023 valida solo el tramo histórico.
-   **Estructura real de los archivos:** el de 1950-2017 tiene un encabezado de una fila (DP, DPNOM, AÑO, ÁREA GEOGRÁFICA, `Hombres_0`…) y pies de nota; el de 2018-2070 tiene dos filas de encabezado (AÑO en la fila 8, nombres por edad en la 9), columnas Total, Hombres y Mujeres, y la hoja de datos es `PobNacionalxÁreaSexoEdad`. Ambos tienen 202 columnas por edad y sexo.
-   **Evidencia:** 14 de 14 puntos de control coinciden en 1950-2017; en 2018-2070 coinciden 3 de 24. Las diferencias incluyen una población total menor (por ejemplo −0.9 % en 2035 y −3.8 % en 2051) y no van en un solo sentido en todos los indicadores. La hoja PPED dice "Actualizado el 18 de Julio de 2025".
-   **Cautelas:** la "edad media" del DANE es el promedio, no la mediana de la ONU; se comparan medianas calculadas con la misma fórmula en ambas fuentes (D21). Las curvas "WPP" que aparecen en el PDF corresponden a una revisión anterior de la ONU y no se reutilizan.
-   **Alternativa descartada:** exigir que el Excel proyectado reproduzca el PDF (son versiones distintas) o usar solo la versión de 2023 (no está disponible en Excel por edad para 2018+ en los archivos descargados).
-   **Validación sustituta:** el script 03 compara la suma por edades con la columna Total del Excel 2018-2070 (pendiente de confirmar al re-ejecutar el 03).
-   **Pendiente:** buscar los indicadores publicados con la actualización de 2025 para construir nuevos puntos de control.

### D21 · Desfase de +1 año en la mediana

-   **Fecha:** 2026-10-28.
-   **Decisión:** la mediana calculada a partir de la población por edad simple supera a `MedianAgePop` en 1.00 año. Para comparar ONU y DANE se usa **siempre la mediana calculada** en ambas fuentes (el desfase se cancela). Al citar el valor oficial de la ONU se usa la columna `MedianAgePop` original.
-   **Evidencia (script 03b):** diferencia media +1.00; desviación 0.02; 99.1 % de las filas dentro de 1.0 ± 0.1; 237 países y todo el periodo; sin variación entre tramos. En Colombia: 32.6 frente a 31.6 en 2023.
-   **Alternativa descartada:** restar 1 a la mediana calculada (no se pudo confirmar con los archivos cuál es la convención estándar; revisar la nota metodológica de la ONU).

### D22 · Geometrías, reparación y recodificaciones

-   **Fecha:** 2026-10-28.
-   **Decisión:**
    1.  Fronteras de Natural Earth, *Admin 0 - Countries*, escala 1:50m (`rnaturalearth` 1.2.0 y `rnaturalearthdata` 1.0.0), sin Antártida; `AUS` se disuelve en un solo país.
    2.  ISO3 = `iso_a3`, completado con `iso_a3_eh` y `adm0_a3` (`iso_a3` trae -99 en varios países).
    3.  Reparación de geometrías **sin s2** y partición en el antimeridiano (`reparar_geometrias()`).
    4.  Separar multipolígonos con `a_partes()`: normalizar a `MULTIPOLYGON` antes de `st_cast(, "POLYGON")`. **Nunca silenciar la advertencia de `st_cast`.**
    5.  Áreas de las partes en proyección cilíndrica de área igual (`+proj=cea`) y punto representativo dentro del polígono más grande.
    6.  Recodificación `KOS` → `XKX` (Kosovo).
    7.  Los departamentos de ultramar de Francia (Reunión, Guadalupe, Martinica, Mayotte y Guayana Francesa) no tienen polígono propio; son parte de Francia en Natural Earth y quedan fuera del universo.
-   **Evidencia (primera ejecución):** franja horizontal en Rusia, línea fina en Fiji y punto de Francia en Córcega. `XKX` era el único país del universo sin polígono (228 de 237 cruzaban).
-   **Causa de los puntos mal ubicados (confirmada):** `st_cast()` sobre un `sfc` de tipo mixto conserva solo la primera parte de cada país. La tabla de control devolvió 1 fila por país con áreas de 164 a 27 033 km² (EE. UU. 185, Indonesia 164, Francia 2 542); el control del antimeridiano de esa versión era vacío por la misma razón.
-   **Causa de la franja:** probable `st_make_valid()` con s2 activo; **no confirmada**.
-   **Evidencia (corrida C):** 1 512 polígonos individuales para 239 países; partes mayores de Francia 538 333 km², Estados Unidos 7 930 922 km² y Rusia 16 531 210 km²; puntos de Francia y Estados Unidos en su territorio continental; 229 de 237 países de WPP con polígono y 161 de 161 del universo.
-   **Alternativas descartadas:** escala 1:10m (innecesaria si el universo cruza completo); centroide del multipolígono (se desplaza hacia el océano en Francia o Noruega); ocultar la franja recortando el mapa.

### D23 · Pesos espaciales

-   **Fecha:** 2026-10-28.
-   **Decisión:** k = 5 vecinos más cercanos por distancia de círculo máximo entre puntos interiores de los polígonos más grandes; pesos estandarizados por filas; sensibilidad con k = 3 y k = 8. Los vecinos expresan cercanía, no frontera común.
-   **Evidencia (corrida C, edad mediana 2023 / 2050 / 2100):** Moran I con k = 3: 0.757 / 0.719 / 0.666; k = 5: 0.738 / 0.707 / 0.651; k = 8: 0.732 / 0.707 / 0.653. LISA significativos (semilla fija): k = 3 → 0 / 0 / 0; k = 5 → 72 / 62 / 42; k = 8 → 83 / 82 / 83. El Moran global casi no depende de k; el conteo de LISA sí.
-   **Alternativa descartada:** contigüidad *queen* (deja islas sin vecinos).

### D24 · Inferencia espacial

-   **Fecha:** 2026-10-28.
-   **Decisión:** pruebas de permutación bilaterales (999 en Moran global, 199 por año en la serie, **4999 en LISA**); corrección FDR de Benjamini-Hochberg **dentro de cada mapa** (familia = países de una variable-año); no se ajusta entre mapas. Todo se reporta como exploratorio. El valor p mínimo alcanzable es 2 / (permutaciones + 1). Cada llamada de LISA lleva su semilla (corrida D) y el conteo de significativos se reporta como **rango** con la estabilidad Monte Carlo (3 semillas).
-   **Evidencia:** con k = 3 no hay ningún LISA significativo ni con 4999 permutaciones: es falta de potencia (el promedio de solo tres vecinos varía mucho y BH exige valores p pequeños), no el piso del valor p. En la corrida C, en 2100 con k = 5, la corrida principal dio 48 significativos y la tabla de sensibilidad 35, con las mismas entradas. **Corrida D (3 semillas): 2023 → 72 a 73; 2050 → 61 a 62; 2100 → 37 a 49**: el conteo de 2100 depende del azar y se reporta como rango. El Moran propio coincide con `spdep::moran.test` (0.7379).
-   **Alternativas descartadas:** valores p analíticos (supuesto de normalidad débil con n = 161); ajuste conjunto entre todos los mapas (queda como sensibilidad opcional).

### D25 · Empalme del DANE en 2017/2018

-   **Fecha:** 2026-10-28.
-   **Decisión:** la serie 1950-2070 del DANE mezcla dos versiones y presenta una ruptura en 2018. El año 2018 se toma de la serie 2018-2070 (base censo 2018). El análisis de soporte (P3) usa **solo 2018-2070** del DANE; el tramo 1950-2017 es contexto. No se calculan tendencias que crucen 2017/2018. La figura del script 03 marca el empalme.
-   **Evidencia:** crecimiento de 1.26 % (2017) a 1.77 % (2018), 2.09 % y 2.28 %; PSR65 de 7.84 a 7.10; mediana de 30.0 a 29.7; diferencia de crecimiento de 0.58 pp respecto a 2016-2017.
-   **Interpretación pendiente:** las causas (base censal de 2018, tratamiento de la migración) deben confirmarse con la metodología del DANE; no se asumen.
-   **Alternativa descartada:** suavizar o ajustar la serie histórica (inventaría datos).
-   **Consecuencia:** los años de cruce del PSR (2027 en adelante) no dependen del empalme.
-   **Observación adicional (figura del script 03, 2026-10-29):** la serie histórica del DANE muestra otra inflexión hacia 1985 y queda muy por debajo de la ONU antes de \~2000 en el soporte 15-64 / 65+. No se investigó; podría estar ligada a la reconstrucción con el censo de ese año (hipótesis sin verificar). Refuerza D27.

------------------------------------------------------------------------

## Propuestas pendientes de confirmación

### D26 · COVID-19 en la validación (antes D21)

**Propuesta.** Los años 2020-2021 son un choque, no tendencia.
En la validación por ventana móvil se reporta el error con y sin esos años, o con un indicador de intervención.
**Evidencia (DANE, estadísticas vitales).** Defunciones totales: 224,332 (2019), 300,829 (2020) y 363,075 (2021).
La esperanza de vida al nacer cae a niveles cercanos a los de 2006 y se recupera desde 2023.

### D27 · Alcance de la comparación ONU-DANE (antes "D22" en el texto del script 03)

**Propuesta.** Las reconstrucciones históricas difieren mucho antes de 1985 (el DANE supera a la ONU en +15.3 % en 1950 y +8.0 % en 1975; +0.1 % en 2000).
Las comparaciones descriptivas se limitan a **2000-2070**; las de soporte demográfico (P3), a **2018-2070** (D25).

------------------------------------------------------------------------

## Resultados del script 03 (actualizado el 2026-10-28)

**Población por edad de la ONU.** Las dos validaciones que habían fallado quedaron explicadas por el script 03b: la diferencia de 2.22 % en la suma por edades es de Holy See y en el universo no supera 1.5e-5 (D19), y el +1.00 año de la mediana es un desfase de convención constante (D21).
Las cifras de soporte demográfico de la ONU **dejan de ser provisionales**; queda por confirmar, al re-ejecutar el 03, la verificación interna del Excel del DANE (suma por edades frente a la columna Total).

**Puntos de control del DANE: 17 de 38** (14 de 14 en 1950-2017 y 3 de 24 en 2018-2070).
Ejemplos del tramo proyectado: población de 2035 = 55,476,504 frente a 55,990,158 del PDF (-0.9 %); 60+ en 2050 = 24.6 % frente a 25.9 %; 0-14 en 2050 = 13.6 % frente a 14.8 %.
La diferencia es compatible con la actualización de julio de 2025 (D20); no es un error de lectura.

**Comparación ONU frente a DANE, Colombia.**

| Año  | Población ONU | Población DANE | DANE frente a ONU |
|------|---------------|----------------|-------------------|
| 1950 | 11.77 M       | 13.57 M        | +15.3 %           |
| 2000 | 39.09 M       | 39.14 M        | +0.1 %            |
| 2023 | 52.32 M       | 52.12 M        | -0.4 %            |
| 2050 | 59.39 M       | 55.65 M        | -6.3 %            |
| 2070 | 57.13 M       | 50.59 M        | -11.4 %           |

**Años de cruce de umbrales (racha de 3 años).**

| Definición  | Umbral | ONU  | DANE |
|-------------|--------|------|------|
| 15-64 / 65+ | 3.0    | 2052 | 2058 |
| 15-64 / 65+ | 2.5    | 2058 | 2064 |
| 15-59 / 60+ | 3.0    | 2038 | 2043 |
| 15-59 / 60+ | 2.5    | 2045 | 2051 |

La ONU cruza cada umbral antes que el DANE: de 5 a 6 años en los umbrales 3.0, 2.5 y 2.0, y 1 año en el umbral 4.0 de 15-59/60+.
En 2050 la ONU tiene 27.2 % de población de 60+ y el DANE 24.6 %.
Esto describe una diferencia entre dos proyecciones oficiales construidas con modelos distintos; no indica cuál es más acertada (D25).
En el mundo, 168 de 237 países cruzan PSR65 \< 3.0 entre 2023 y 2100.

------------------------------------------------------------------------

## Decisiones abiertas

| \# | Pregunta | Cuándo se cierra | Insumo |
|----|----|----|----|
| D10 | Indicadores del PCA y clustering | Fase 2 | Matriz de correlación |
| D11 | Idioma del reporte final y de las figuras (afecta separadores decimales y etiquetas) | Cuanto antes | Bases del concurso |
| D15 | Regla de transición entre arquetipos | Fase 3 | Clustering |
| D16 | Validación de pronósticos y banda del 80 % | Fase 3 | Resultados de la validación |
| D17 | Efecto de la migración en todo el universo | Antes de la Fase 3 | `02_efecto_migracion.csv` |
| D26 | COVID-19 en la validación | Fase 3 | Equipo |
| D27 | Alcance de la comparación ONU-DANE | Antes del reporte | Equipo |

------------------------------------------------------------------------

## Plantilla para nuevas decisiones

```         
## Dn · Título

**Decisión.**
**Justificación.**
**Alternativas descartadas.**
**Evidencia.** (consulta o script, resultado numérico)
**Impacto.** (qué código o figura cambia)
**Fecha / Estado.**
```
