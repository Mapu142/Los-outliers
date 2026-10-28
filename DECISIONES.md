# Registro de decisiones · ASA DataQuest 2026 (WPP 2024)

Este documento es la **única fuente de verdad** sobre cómo se tratan los datos. Cada decisión se toma una vez, se justifica con evidencia reproducible y todo el código posterior la hereda. Si una decisión cambia, **no se borra**: se marca como *Reemplazada* y se agrega una nueva con su fecha.

Vínculo con las guías de la ASA (2022): este registro cumple B1 (comunicar fuentes, procesamiento y manejo de faltantes), B2 (transparencia en supuestos) y F4 (reproducibilidad).

**Fecha de la Fase 0:** 2026-10-20 · **Script de evidencia:** `scripts/00_setup_exploracion_wpp2024.R` · **Parámetros:** `R/config.R`

---

## Resumen

| # | Decisión | Estado | Fecha |
|---|---|---|---|
| D1 | País = `ISO3_code` no nulo (237 países/áreas) | ✅ Cerrada | 2026-10-20 |
| D2 | Estimación `Time ≤ 2023`; proyección `Time ≥ 2024` | ✅ Cerrada | 2026-10-20 |
| D3 | Análisis hasta 2100; 2101 solo trae `TPopulation1Jan` | ✅ Cerrada | 2026-10-20 |
| D4 | Holy See sin suplemento: se excluye de análisis con `LE60` o nacimientos por sexo | ✅ Cerrada | 2026-10-20 |
| D5 | Agregados solo como referencia; nunca se suman con países | ✅ Cerrada | 2026-10-20 |
| D6 | Sin imputación; `DoublingTime` está censurado y no entra en modelos | ✅ Cerrada | 2026-10-20 |
| D7 | Tolerancia de nacimientos por sexo = 0.0011 | ✅ Cerrada | 2026-10-20 |
| D8 | Cobertura de OtherVariants para el análisis de incertidumbre | ✅ Cerrada | 2026-10-20 |
| D9 | Peso igual por país para arquetipos; ponderado por población para cifras globales | 🟡 Propuesta | 2026-10-20 |
| D10 | Indicadores para PCA y clustering | 🟡 Propuesta | 2026-10-20 |
| D11 | Idioma del reporte y de las figuras finales | ⏳ Abierta | — |
| D12 | Universo de análisis: países con población ≥ 1 millón (2023) para clustering y rankings (161 países) | ✅ Cerrada | 2026-10-20 |
| D13 | Datos externos: permitidos e incentivados; registro obligatorio en `FUENTES.md` | ✅ Cerrada | 2026-10-20 |
| D14 | Banda oficial = [mínimo, máximo] del par Lower/Upper PI, no las etiquetas | ✅ Cerrada | 2026-10-20 |
| D15 | Transición de grupo = ≥ 5 años consecutivos en el nuevo grupo | 🟡 Propuesta | 2026-10-20 |
| D16 | Validación por ventana móvil (5/10/20 años); discrepancia = fuera de la banda del 80 % | 🟡 Propuesta | 2026-10-20 |
| D17 | Migración: no se excluye; se cuantifica con `Zero migration` y se hace análisis de sensibilidad sin los países dependientes de ella | 🟡 Propuesta refinada | 2026-10-20 |
| D18 | Soporte demográfico en dos definiciones: PSR65 = 15-64 / 65+ y PSR60 = 15-59 / 60+ (fuente externa); umbrales 3.0 y 2.5 como escenarios | 🟡 Propuesta | 2026-10-20 |
| D19 | Estructura por edad con fecha de referencia 1 de julio (igual que `TPopulation1July`, `MedianAgePop` y el DANE, 30 de junio) | 🟡 Propuesta | 2026-10-20 |
| D20 | DANE como fuente secundaria: solo serie nacional, Área = Total, versión post-COVID verificada con puntos de control; el PDF es documentación, no dato | 🟡 Propuesta | 2026-10-20 |
| D21 | COVID-19 (2020-2021) como choque estructural en la validación de pronósticos | 🟡 Propuesta | 2026-10-20 |

---

## D1 · Definición de país

**Decisión.** Un registro es un país o área si y solo si `ISO3_code` no es nulo ni vacío. No se usa `LocTypeName` para filtrar.

**Justificación.** El campo `Location` mezcla países con agregados regionales, de ingreso y grupos ad hoc. Sumar sin filtrar duplica la población. `LocTypeName` no sirve como filtro porque 234 ubicaciones lo tienen en `NA`.

**Alternativas descartadas.**
- Filtrar por `LocTypeName = 'Country/Area'`: coincide hoy con ISO3 (237), pero depende de un campo que la guía advierte como inconsistente.
- Filtrar por lista manual de nombres: frágil y no reproducible.

**Evidencia.**
- 237 ubicaciones con ISO3 + 318 agregados = 555 ubicaciones.
- Suma de `TPopulation1July` de los 237 países frente a la fila `World`: diferencia máxima de **0.0000 %** en 1950-2100.
- Los 237 de `Country/Area` tienen ISO3; las otras categorías tienen 0.

**Impacto.** Todo análisis a nivel país parte de `medium_paises`. Incluye Holy See (237 y no 236).

**Implementación.** `SQL_ES_PAIS` en `R/utils_datos.R`; secciones 3 y 4 del script 00.

---

## D2 · Estimación frente a proyección

**Decisión.** Los años hasta 2023 (`CFG$ultimo_anio_estimado`) son estimaciones; desde 2024 son proyección de la variante Medium. Toda tabla analítica lleva la columna `tipo_dato`.

**Justificación.** La documentación de la ONU y del concurso lo establece así. Mezclar ambas como si fueran observaciones sesga las conclusiones, y la proyección es un escenario, no un hecho.

**Alternativas descartadas.** Tratar la serie como continua sin marca.

**Evidencia.** OtherVariants comienza en 2024 y solo contiene proyecciones, lo que es consistente con el corte.

**Impacto.** Los gráficos muestran el corte con una zona sombreada y línea punteada (`capa_proyeccion()` en `R/tema.R`). Los modelos se ajustan sobre estimaciones y la proyección se usa como contraste.

---

## D3 · Año final del análisis

**Decisión.** El análisis llega hasta **2100** (`CFG$ultimo_anio_analisis`). El año 2101 solo se usaría para `TPopulation1Jan`.

**Justificación.** En 2101 las 237 filas de países traen únicamente `TPopulation1Jan`; los otros 53 indicadores están vacíos. `TPopulation1Jan` de 2101 equivale al cierre de 2100. Incluir 2101 introduciría faltantes artificiales en modelos, clusters y gráficos.

**Alternativas descartadas.** Mantener 2101 y tratarlo como faltante: contamina el conteo de `NA` y complica cada modelo.

**Evidencia.**
- Indicadores con datos en 2101 (todos los 54 evaluados): solo `TPopulation1Jan` (237 filas).
- 2099 y 2100: 237 de 237 filas completas en `TPopulation1July`, `TFR`, `LEx` y `Births`.
- La comparación con `World` da `NA` únicamente en 2101.
- El suplemento también termina en 2100.

**Impacto.** La tabla maestra tiene 237 × 151 = **35,787 filas**. Medium y suplemento cubren los mismos años.

---

## D4 · Holy See y el suplemento

**Decisión.** Holy See (`VAT`, LocID 336) no tiene filas en el suplemento. Se excluye de cualquier análisis que use `BirthsMale`, `BirthsFemale`, `LE60`, `LE60Male` o `LE60Female`. En los demás análisis permanece.

**Justificación.** La documentación del suplemento lo indica: Holy See aparece en Medium pero no estaba en las descargas del portal. No se imputa, porque no hay una base razonable para ello.

**Alternativas descartadas.** Imputar con la media regional (sin sustento); eliminar Holy See de todo el proyecto (pérdida innecesaria de información).

**Evidencia.**
- Países de Medium sin filas en el suplemento: únicamente Holy See.
- Tras el `LEFT JOIN`, `LE60` es `NULL` solo para Holy See, en **151 filas** (1950-2100).

**Impacto.** Los análisis con suplemento usan 236 países; el resto, 237. Debe indicarse en cada figura o tabla donde aplique.

---

## D5 · Agregados regionales

**Decisión.** Las 318 filas de agregados (regiones, grupos de ingreso, mundo, etc.) se usan solo como referencia de contraste y para validar totales. Nunca se suman ni se promedian junto con países.

**Justificación.** Cada agregado ya contiene a los países que lo componen; combinarlos duplica el peso de esos países.

**Evidencia.** Vista `medium_agregados`; la fila `World` se usa como control de la suma de países (D1).

**Impacto.** El reporte y la app distinguen explícitamente "país" de "agregado".

---

## D6 · Faltantes y `DoublingTime`

**Decisión.** No se imputa ningún valor. `DoublingTime` presenta **censura estructural** y se trata así:
- No entra en PCA, clustering ni modelos.
- Su información útil está contenida en `PopGrowthRate`.
- En gráficos descriptivos se muestra solo donde existe, con una nota explícita.

**Justificación.** Tras recortar a 2100, **52 de 54 indicadores están completos** para los 237 países. `DoublingTime` es el único con `NA` (15,938 filas, 44.5 %), y esos `NA` no son aleatorios: el indicador no existe cuando el crecimiento anual es ≤ 0.5 %. Una población que no crece (o crece muy poco) no tiene un tiempo de duplicación razonable. Imputarlo inventaría valores inexistentes y usar solo las filas completas sesgaría la muestra hacia países en crecimiento.

**Alternativas descartadas.**
- Imputar con un valor muy alto o con la media: crea datos que no existen.
- Eliminar las filas con `NA`: elimina casi la mitad de los registros y sesga hacia países en crecimiento.
- Calcular `DoublingTime` propio: sustituiría la definición de la ONU sin necesidad.

**Evidencia.**

| Condición | Filas | `DoublingTime = NA` |
|---|---|---|
| Crecimiento ≤ 0 (en `medium_paises`) | 10,604 | 10,604 (100 %) |
| Crecimiento > 0 y ≤ 0.5 | 5,334 | 5,334 (100 %) |
| Crecimiento > 0.5 | — | 0 |

- Estimación: `NA` con crecimiento de 0.001 a 0.500; con dato, de 0.501 a 37.9.
- Proyección: `NA` con crecimiento de 0.001 a 0.500; con dato, de 0.501 a 4.41.
- Los rangos no se solapan en ninguno de los dos periodos (a la precisión de 4 decimales de esa consulta). El script 00 (sección 9) reporta el umbral exacto sin redondeo.

**Impacto.** `CFG$umbral_doubling = 0.5`. No hay imputación en ninguna parte del proyecto.

---

## D7 · Tolerancia de nacimientos por sexo

**Decisión.** La tolerancia para verificar `BirthsMale + BirthsFemale = Births` es **0.0011** (`CFG$tol_births`).

**Justificación.** El suplemento documenta una coincidencia "dentro de 0.001". Con ese umbral exacto, el punto flotante marca como violación a filas cuya diferencia es exactamente 0.001. No es una inconsistencia de los datos.

**Alternativas descartadas.** Mantener 0.001 y tratar las filas marcadas como errores del suplemento (diagnóstico incorrecto).

**Evidencia.**
- Con tolerancia 0.001: 4,852 de 35,636 filas (13.6 %) fuera de tolerancia.
- Diferencia máxima observada: **0.001**.
- Con tolerancia 0.0011: **0** filas fuera.

**Impacto.** El suplemento es coherente con `Births`. Para tasas por sexo con pocos nacimientos, usar `SRB` de Medium, como indica su documentación.

---

## D8 · Cobertura de OtherVariants

**Decisión.** Para el análisis de incertidumbre (Paso 15):
- Los países se filtran por `ISO3_code`, igual que en Medium (D1).
- El análisis llega hasta **2100**: en todas las variantes, el año 2101 solo trae `TPopulation1Jan` (D3).
- Los **intervalos** (Lower/Upper 80 PI, Lower/Upper 95 PI, Median PI) se usan solo para los 47 indicadores que traen.
- **`Mean` no sustituye a `Medium`**: solo trae `TFR`, `LExMale` y `LExFemale`.
- `Constant mortality` se usa solo para los 30 indicadores que trae.

**Justificación.** Las variantes no son homogéneas: no todas reportan los mismos indicadores ni las mismas ubicaciones. Asumir lo contrario produciría comparaciones con huecos silenciosos.

**Alternativas descartadas.** Usar `Mean` como proxy de Medium (no coincide); incluir 2101 (incompleto).

**Evidencia.**

| Hecho | Resultado |
|---|---|
| Países por variante | 237 en las 18 variantes |
| Escenarios (11 de 12) | 54 indicadores con datos |
| `Constant mortality` | 30 indicadores con datos |
| Intervalos PI | 321 ubicaciones = 237 países + 84 agregados; 47 indicadores |
| Indicadores ausentes en PI | `NRR`, `SRB`, `DeathsMale`, `DeathsFemale`, `InfantDeaths`, `LBsurvivingAge1`, `Under5Deaths` |
| `Mean` | 237 países, 2024-2100; solo `TFR`, `LExMale`, `LExFemale` |
| `Mean` frente a `Medium` | Diferencia absoluta máxima en `TFR`: 0.274 (no son equivalentes) |
| 2101 en todas las variantes | Solo `TPopulation1Jan` |

**Impacto.** Las medidas de incertidumbre se construyen sobre `TPopulation1July`, `TFR` y `LEx`, presentes en High, Low y los intervalos. Los indicadores ausentes de los intervalos no tendrán banda de incertidumbre y se dirá explícitamente.

---

## Decisiones propuestas tras la propuesta del equipo (pendientes de confirmación)

Estas decisiones salen de `PLAN_ANALITICO.md` y de los scripts 01 y 02. Estado 🟡 = propuesta del consultor que el equipo debe confirmar o modificar. Cuando se confirmen, se cambia el estado y se añade la evidencia.

### D9 · Ponderación
**Propuesta.** Peso igual por país para tipologías y clustering (la unidad de interés es el país); ponderado por población para cifras globales y comparaciones de carga demográfica mundial.
**Justificación.** Las medianas sin ponderar (p. ej. TFR mediano 2023 = 1.95) responden a "¿cómo es el país típico?", no a "¿cómo vive la gente?". Son preguntas distintas y deben rotularse.

### D10 · Indicadores del PCA y clustering
**Propuesta.** Candidatos: `TFR`, `LE60` (o `LEx`), `MedianAgePop`, índice vital (`Births/Deaths`, en logaritmo) y ganancia de edad mediana a 10 años. Excluir `DoublingTime` (D6) y evitar versiones por sexo del mismo indicador.
**Cierre.** Tras la matriz de correlación de la Fase 2.

### D12 · Universo de análisis
**Propuesta.** Descriptivo con los 237 países y áreas; clustering, rankings y autocorrelación espacial solo con países de 1 millón de habitantes o más en 2023.
**Evidencia.** En el ranking de velocidad de envejecimiento del script 01, los diez primeros puestos son territorios pequeños (Saint Martin 11.4 años por década en 2027, Cook Islands, Maldivas…); Colombia no aparece. Su volatilidad responde al tamaño pequeño y no a un patrón generalizable.
**Cierre.** Con el conteo por umbral del script 02.

### D13 · Datos externos
**Decisión.** Confirmado por el equipo: el concurso incentiva complementar con otras fuentes. Toda fuente se registra en `data/raw/externos/FUENTES.md` (URL, fecha, licencia, transformaciones) antes de usarse. Unión por `ISO3_code`; países sin correspondencia, listados.

### D14 · Banda oficial de incertidumbre
**Propuesta.** La banda se construye como [mínimo, máximo] del par Lower/Upper de cada nivel (80 % y 95 %).
**Evidencia.** Para la edad mediana de Colombia, "Lower 80 PI" da **mayor** edad que "Upper 80 PI" (46.2 frente a 41.5 en 2050; 59.6 frente a 47.2 en 2100). Las etiquetas no siguen el orden numérico del indicador.
**Cierre.** Con el script 02, sección 2 (proporción de países donde Lower < Upper, por indicador).

### D15 · Regla de transición de grupo
**Propuesta.** Un país pasa al grupo B en el primer año desde el cual permanece en B al menos 5 años consecutivos. Sensibilidad con 3 y 10. Se reporta con rango.

### D16 · Validación del pronóstico y discrepancia con la ONU
**Propuesta.** Ventana móvil dentro de 1950-2023 con horizontes de 5, 10 y 20 años, contra líneas base ingenua y de deriva. Un pronóstico propio "discrepa" de la ONU solo si cae fuera de la banda del 80 %. La extrapolación a 2100 es ilustrativa.
**Evidencia.** Hay 74 años de historia por país frente a 77 años a proyectar (relación 1.04); no se puede validar un horizonte de 77 años.
**Incertidumbre oficial de referencia (Colombia, edad mediana).** Ancho del 80 %: 4.7 años (2050) y 12.4 años (2100). Ancho del 95 %: 7.6 y 21.9.

### D17 · Migración
**Propuesta.** No se excluye de las variables; se cuantifica comparando `Medium` con `Zero migration`.
**Evidencia.** Colombia, edad mediana: 43.7 frente a 43.9 en 2050; 51.8 frente a 51.8 en 2100. Falta la comparación en todos los países (script 02, sección 3).

### D18 · Soporte demográfico
**Propuesta.** PSR = población 15-64 / población 65+, calculado con datos externos de población por edad (los cuatro archivos entregados no la traen: el script 01 lo verificó). Umbrales de 3.0 y 2.5 declarados como escenarios, con sensibilidad a 2.0 y 4.0. Año de cruce = primera vez que queda por debajo al menos 3 años seguidos, reportado con rango entre variantes.
**Límite.** El PSR no mide sostenibilidad fiscal de un sistema pensional.

---

### D18 (ampliación) · Dos definiciones de soporte
**Propuesta.** Se calculan PSR65 (población 15-64 / 65+, definición internacional) y PSR60 (15-59 / 60+, la que usa el DANE en sus indicadores de estructura). Las edades de jubilación vigentes en Colombia (57 mujeres y 62 hombres, según prensa; confirmar con fuente oficial) quedan entre ambas definiciones, por lo que se reportan las dos y se usa la diferencia como medida de sensibilidad.

### D19 · Fecha de referencia de la población por edad
**Propuesta.** Una sola fecha para toda la serie: **1 de julio**. Coincide con `TPopulation1July`, con `MedianAgePop` y con el DANE (proyecciones a 30 de junio). Mezclar el 1 de julio de 1950-2023 con el 1 de enero de 2024-2100 introduce un desfase de medio año en el empalme.
**Evidencia.** El equipo descargó julio 1950-2023, enero 1950-2023 y enero 2024-2100. Falta julio 2024-2100. Si no se descarga, el script 03 usa la serie completa del 1 de enero y lo advierte; esa base solo se valida contra `TPopulation1Jan`.
**Validación.** La suma por edades debe reproducir `TPopulation1July` (o `TPopulation1Jan`) de la tabla maestra, y la mediana calculada debe reproducir `MedianAgePop`.

### D20 · DANE como fuente secundaria
**Propuesta.** Se usa la serie nacional por edad simple (1950-2017 y 2018-2070), filtrada a Área Geográfica = Total (sin ese filtro la población se triplica: Cabecera + Rural + Total). Para empalmar, el año 2018 se toma de la serie 2018-2070 (base censo 2018). La versión se acepta solo si reproduce los puntos de control del PDF del DANE (marzo de 2023, actualización posterior a la pandemia): 2035 con 55,990,158 personas, y las estructuras por edad de 2035 y 2050.
**Cautelas.** El PDF es de marzo de 2023: el DANE puede haber publicado revisiones. La "edad media" del DANE es el promedio, no la mediana de la ONU; se comparan medianas calculadas con la misma fórmula en ambas fuentes. Las curvas "WPP" que aparecen en el PDF corresponden a una revisión anterior de la ONU y no se reutilizan.

### D21 · COVID-19 en la validación
**Propuesta.** Los años 2020-2021 son un choque, no tendencia. En la validación por ventana móvil se reporta el error con y sin esos años, o con un indicador de intervención.
**Evidencia (DANE, estadísticas vitales).** Defunciones totales: 224,332 (2019), 300,829 (2020) y 363,075 (2021). La esperanza de vida al nacer cae a niveles cercanos a los de 2006 y se recupera desde 2023.

### Resultados del script 02 (2026-10-20)

**D12 · Universo.** Con umbral de 1 millón de habitantes (2023) quedan **161 países** y se excluyen 76, que suman el **0.21 %** de la población mundial. Dentro del universo, Colombia ocupa el puesto **22** en velocidad de envejecimiento (4.7 años por década; máximo anual en 2037). El ranking ya no lo dominan territorios pequeños (Puerto Rico, Hong Kong, Taiwán, Singapur y Corea encabezan).

**D14 · Orden de las bandas.** Proporción de países donde "Lower 80 PI" es numéricamente menor que "Upper 80 PI":

| Indicador | 2050 | 2100 |
|---|---|---|
| `TFR` | 1.000 | 1.000 |
| `LEx` | 1.000 | 1.000 |
| `MedianAgePop` | **0.034** | **0.063** |

Las etiquetas siguen el orden normal en fecundidad y esperanza de vida, pero están **invertidas** en la edad mediana (menos fecundidad implica población más envejecida). Regla: la banda siempre se construye como [mínimo, máximo] del par. Además, `Medium` cae dentro de la banda del 80 % en el **96.0 %** de los país-año (n = 18,249); el 4 % restante se revisará, porque `Medium` es una proyección determinística y no la mediana probabilística.

**D17 · Migración.** Diferencia en edad mediana (`Zero migration` menos `Medium`), 161 países:

| Año | Mediana | Rango | Países con |dif| > 2 años |
|---|---|---|---|
| 2050 | -0.03 | de -3.4 a +23.6 | 37 de 161 |
| 2100 | -0.30 | de -4.4 a +23.0 | 54 de 161 |

La migración es irrelevante para Colombia (0.21 años en 2050; 0 en 2100) pero **domina** la edad mediana de varios países (Emiratos Árabes Unidos +23.0, Qatar +18.6, Kuwait +18.0, Bahréin +14.6, Arabia Saudita +12.4, Omán +12.2, Canadá +9.4, Australia +7.7 en 2100). Esos países se agruparían por su migración, no por su envejecimiento natural. Propuesta: el clustering se repite sin los países con |dif| > 2 años como análisis de sensibilidad y se prefieren indicadores poco dependientes de la migración (`TFR`, `LE60`).

---

## Decisiones abiertas

| # | Pregunta | Cuándo se cierra | Insumo |
|---|---|---|---|
| D11 | Idioma del reporte final y de las figuras (afecta separadores decimales y etiquetas). Verificar las reglas del concurso | Paso 5 | Bases del concurso |

---

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