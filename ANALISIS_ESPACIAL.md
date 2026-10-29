# Análisis espacial · bitácora de resultados y observaciones

**Documento vivo.** Registra qué se hizo, qué se encontró y qué sigue en la ampliación espacial (scripts 04, 05 y 06). Todo el análisis es **exploratorio** (`PLAN_ANALITICO.md`, sección 7). Última actualización: 2026-10-28.

> **Estado de los números.** Las corridas A y B de este documento se hicieron con **puntos representativos defectuosos** para los países con varias partes (ver sección 3). Sirven para documentar el proceso y el orden de magnitud, **no** para citarse en el reporte. La corrida C (con `a_partes()`) está pendiente y reemplaza a las anteriores.

------------------------------------------------------------------------

## 1. Pregunta y alcance

¿Los países con envejecimiento, fecundidad y longevidad parecidos están cerca unos de otros, y dónde se concentran esos patrones? ¿Cambia eso entre la estimación (2023) y la proyección (2050, 2100)? ¿Dónde queda Colombia?

Es un insumo para P1 (arquetipos) del plan: describe estructura espacial, no explica causas. No hay análisis subnacional: WPP solo trae países.

## 2. Datos y decisiones

| Elemento | Decisión | Referencia |
|----|----|----|
| Universo | Países con ≥ 1 millón de habitantes en 2023: **161** | D12 |
| Variables | Edad mediana (`MedianAgePop`), TFR, esperanza de vida al nacer, y máxima ganancia de edad mediana en una década (2024-2100) | Plan §4 |
| Fronteras | Natural Earth 1:50m, ISO3 completado con `iso_a3_eh` y `adm0_a3`; Kosovo `KOS`→`XKX` | D22 |
| Vecinos | 5 vecinos más cercanos, distancia de círculo máximo entre puntos interiores del polígono más grande; sensibilidad con k = 3 y 8 | D23 |
| Inferencia | Permutaciones bilaterales (999 en Moran global, 4999 en LISA); FDR (BH) dentro de cada mapa | D24 |

Los vecinos expresan **cercanía**, no frontera común (Colombia queda vecina de Costa Rica o Panamá aunque no compartan frontera terrestre).

## 3. Auditoría de las geometrías

| \# | Hallazgo | Causa | Estado |
|----|----|----|----|
| 1 | Franja horizontal en el mapa (Rusia) y línea fina (Fiji) | Polígonos que cruzan los 180° tras `st_make_valid()` con s2 activo (causa probable) | Corregido con `reparar_geometrias()`; los mapas ya se ven bien |
| 2 | Kosovo sin polígono | Natural Earth usa `KOS`; WPP usa `XKX` | Recodificado; universo 161 de 161 |
| 3 | Punto de Francia en Córcega; Indonesia en Sumatra | Ver hallazgo 4 | Corregido, pendiente de re-ejecutar |
| 4 | **La tabla de control devolvía 1 fila por país con áreas de 164 a 27 033 km² (EE. UU. 185, Indonesia 164, Francia 2 542)** | `st_cast(x, "POLYGON")` sobre una geometría de tipo mixto conserva solo la primera parte de cada país, y yo había silenciado la advertencia con `suppressWarnings()`. Confirmado por la salida del 04 | Corregido con `a_partes()`: normaliza a `MULTIPOLYGON` antes de separar |
| 5 | El control del antimeridiano del 04 "pasaba" sin probar nada | Miraba solo la primera parte de cada país | Corregido; ahora usa `a_partes()` |

**Consecuencias.** Los mapas no se ven afectados (dibujan la geometría completa). Sí se afectan los puntos representativos de los países con varias partes (Estados Unidos, Francia, Rusia, Indonesia, Noruega y otros), y con ellos los vecinos y todo Moran/LISA. Un indicio: entre las corridas A y B, los vecinos de Colombia pasaron de {Costa Rica, Ecuador, Panamá, Perú, Venezuela} a {Costa Rica, Ecuador, Nicaragua, Panamá, Perú}.

**Controles nuevos** (el 04 y el 06 se detienen si fallan): más de 1,5 polígonos individuales por país en promedio; partes mayores plausibles (Francia \> 4e5, Estados Unidos \> 7e6, Rusia \> 1.4e7 km²); puntos de Francia y Estados Unidos dentro de su territorio continental; ningún polígono individual con amplitud \> 180° de longitud.

## 4. Registro de corridas

### Corrida A · primera ejecución (160 países; puntos defectuosos; LISA con 999 permutaciones)

| Variable                   | 2023  | 2050  | 2100  |
|----------------------------|-------|-------|-------|
| Moran I, edad mediana      | 0.747 | 0.715 | 0.650 |
| Moran I, TFR               | 0.718 | 0.700 | 0.640 |
| Moran I, esperanza de vida | 0.671 | 0.679 | 0.669 |

Velocidad de envejecimiento: I = 0.327. LISA significativos (k = 5), alto-alto / bajo-bajo / alto-bajo / bajo-alto / no significativo: 2023 → 35 / 36 / 1 / 0 / 88; 2050 → 28 / 35 / 1 / 2 / 94; 2100 → 5 / 21 / 1 / 0 / 133. Con k = 3 y 499 permutaciones no salió ningún LISA significativo. Colombia: no significativa (p con FDR 0.98, 0.62, 0.24, 0.42).

### Corrida B · segunda ejecución (161 países; puntos aún defectuosos; LISA con 4999 permutaciones)

| Variable                   | 2023  | 2050  | 2100  |
|----------------------------|-------|-------|-------|
| Moran I, edad mediana      | 0.720 | 0.713 | 0.670 |
| Moran I, TFR               | 0.690 | 0.676 | 0.626 |
| Moran I, esperanza de vida | 0.631 | 0.639 | 0.632 |

Velocidad de envejecimiento: I = 0.300. El Moran propio coincide con `spdep::moran.test` (0.7196).

| k   | LISA significativos 2023 | 2050 | 2100 | Moran I 2023 |
|-----|--------------------------|------|------|--------------|
| 3   | 0                        | 5    | 3    | 0.740        |
| 5   | 71                       | 66   | 26   | 0.720        |
| 8   | 76                       | 88   | 80   | 0.680        |

LISA con k = 5: 2023 → 32 alto-alto, 39 bajo-bajo, 90 no significativos; 2050 → 29 / 37 / 95; 2100 → 5 alto-alto, 21 bajo-bajo, 1 alto-bajo, 134 no significativos; velocidad → 4 alto-alto, 2 bajo-bajo, 1 alto-bajo, 1 bajo-alto, 153 no significativos. Colombia: no significativa en todos (p con FDR 0.97, 0.65, 0.24, 0.42; rezago estandarizado −0.05, 0.30, 0.67, 0.58).

Moran de la edad mediana por año (A / B): 1950 → 0.627 / 0.559; 1975 → 0.713 / 0.664; 2000 → 0.727 / 0.680; 2023 → 0.747 / 0.720; 2050 → 0.715 / 0.713; 2075 → 0.663 / 0.679; 2100 → 0.650 / 0.670.

### Corrida C · con `a_partes()` (PENDIENTE)

Ejecutar 04, 05 y 06 y pegar aquí el contenido de `output/tablas/06_resumen_corrida.md`.

## 5. Observaciones

**Lo que parece estable** (se mantuvo entre A y B, aunque los puntos eran distintos; reconfirmar con la corrida C):

1.  **Autocorrelación espacial positiva y fuerte.** Moran I entre 0.56 y 0.75 en edad mediana y TFR, siempre con el valor p en su piso. Los países parecidos están cerca unos de otros.
2.  **El patrón se debilita en la proyección.** La edad mediana pasa de \~0.72-0.75 (2023) a \~0.65-0.67 (2100); el TFR de \~0.69-0.72 a \~0.63-0.64. La esperanza de vida casi no cambia.
3.  **La agrupación era menor en 1950** (0.56-0.63) y subió hasta \~2023.
4.  **Colombia no forma parte de ningún grupo local significativo** en ninguna corrida: sus vecinos más cercanos tienen valores parecidos al promedio mundial (rezago estandarizado cercano a 0 en 2023).
5.  **La velocidad de envejecimiento se agrupa mucho menos** (I ≈ 0.30-0.33) que los niveles.

**Lo que no es estable o no se puede afirmar todavía:**

-   **El conteo de LISA depende mucho de k.** Con k = 3 casi nada sale significativo; con k = 5 y 8, decenas. No se debe reportar un único número de "clusters".
-   **El tamaño del error de los puntos es del orden de 0.03-0.04 en Moran I** (diferencias entre A y B: 0.747 → 0.720 en edad mediana; 0.671 → 0.631 en esperanza de vida). Cualquier cambio de esa magnitud entre años o variables debe leerse con cautela.
-   **El leve descenso 2023 → 2100** (≈ 0.05-0.08) es del mismo orden que ese error; la corrida C debe confirmar si se mantiene.

**Hipótesis sin verificar** (no afirmar en el reporte sin pruebas):

-   Moran ≈ 0.7 refleja sobre todo gradientes continentales (África joven; Europa y Asia oriental envejecidas), no vecindades locales.
-   Parte del patrón proyectado puede venir del método de la ONU (modelos que comparten información entre países), no de una dinámica regional real.
-   La pérdida de agrupación en 2100 podría deberse a la convergencia de los supuestos de fecundidad.

## 6. Limitaciones

-   Unidad de análisis: país. Resultados dependen del tamaño y la forma de las fronteras (problema de la unidad de área modificable). Un país como Rusia o Estados Unidos se resume en un solo punto.
-   Cercanía no es frontera: la matriz de pesos kNN mezcla vecinos contiguos y vecinos al otro lado del mar.
-   2023 es estimación; 2050 y 2100 son proyecciones de la variante Medium, no observaciones.
-   BH se aplica dentro de cada mapa, no entre mapas; el análisis completo incluye cientos de pruebas locales.
-   Los territorios pequeños quedan fuera del universo (\< 1 millón) y de Moran/LISA, aunque aparecen en los mapas descriptivos.
-   Los grupos LISA describen patrones; no son etiquetas sobre los países (principio D6 de la ASA).

## 7. Pendientes y próximos pasos

-   [ ] Re-ejecutar 04, 05 y 06 y registrar la corrida C (reemplaza A y B como fuente de cifras).
-   [ ] Revisar `06_moran_dispersion.png`, `06_moran_serie_temporal.png` y los dos mapas LISA.
-   [ ] Probar una definición alternativa de vecinos (por ejemplo, banda de distancia) y comparar con kNN.
-   [ ] Medir cuánto cambia el resultado con otro punto representativo (centroide frente a punto interior del polígono mayor).
-   [ ] Moran dentro de grandes regiones, para separar gradiente continental de agrupación local.
-   [ ] LISA o conteo de uniones sobre los arquetipos del clustering, cuando exista (Fase 3).
-   [ ] Análisis subnacional de Colombia: requiere proyecciones departamentales y fronteras del DANE; fuentes nuevas, por registrar en `FUENTES.md` antes de usarlas.

## 8. Reproducibilidad

``` text
scripts/04_espacial_geometrias.R   fronteras, cruce ISO3, puntos representativos
scripts/05_espacial_mapas.R        mapas coropléticos
scripts/06_espacial_moran_lisa.R   Moran, LISA, sensibilidad, figuras y resumen .md
R/utils_espacial.R                 kNN, Moran, LISA, a_partes(), reparar_geometrias(), mapas
```

Semilla: `set.seed(2026)`. Paquetes: `sf`, `rnaturalearth` 1.2.0, `rnaturalearthdata` 1.0.0, `spdep` (opcional, verificación cruzada). Tablas en `output/tablas/06_*.csv`; figuras en `output/figuras/05_*.png` y `06_*.png`.
