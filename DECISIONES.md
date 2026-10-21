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
| D9 | Análisis por país (peso igual) o ponderado por población | ⏳ Abierta | — |
| D10 | Indicadores para PCA y clustering | ⏳ Abierta | — |
| D11 | Idioma del reporte y de las figuras finales | ⏳ Abierta | — |

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

## Decisiones abiertas

| # | Pregunta | Cuándo se cierra | Insumo |
|---|---|---|---|
| D9 | ¿Medianas y comparaciones entre países con peso igual o ponderadas por población? Depende de la pregunta (tipologías de países: peso igual; carga demográfica mundial: ponderado) | Paso 6 | Plan analítico |
| D10 | Selección de indicadores no redundantes para PCA y clustering (evitar `LEx` con `LExMale`/`LExFemale`, `Births` con `CBR`, y excluir `DoublingTime`) | Paso 6 | Matriz de correlación (Paso 9) |
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
