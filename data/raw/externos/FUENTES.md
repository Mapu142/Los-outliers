# Registro de fuentes · ASA DataQuest 2026

Regla del proyecto (D13): **ninguna fuente externa se usa sin una entrada completa en este archivo** (qué es, URL, archivo local, fecha de descarga, licencia, transformaciones y versión).

Ubicación: `data/raw/externos/FUENTES.md`. Última actualización: 2026-10-29.

> **Cómo leer este archivo.** Lo que consta en los scripts, las salidas o los archivos del proyecto está escrito como dato. Lo que **no consta** está marcado **[COMPLETAR]** y debe llenarlo quien descargó el archivo (fecha de descarga, URL exacta, condiciones de uso). No se rellenó con suposiciones.

------------------------------------------------------------------------

## 1. Resumen

| ID | Fuente | Uso en el proyecto | Estado |
|----|----|----|----|
| E0 | ONU, WPP 2024: archivos entregados por el concurso (Medium, OtherVariants, notas, suplemento) | Base de todo el análisis | ✅ En uso |
| E1 | ONU, WPP 2024: población por edad simple y sexo, variante Medium | PSR, mediana calculada | ✅ En uso (script 03) |
| E2 | DANE: proyecciones nacionales de población por área, sexo y edad (PPED) | Segunda proyección oficial de Colombia (P3) | ✅ En uso (script 03) |
| E2-doc | DANE: presentación de indicadores demográficos (marzo de 2023) y tabla de puntos de control | Documentación y validación | ✅ En uso (script 03) |
| E3 | Parámetros pensionales de Colombia | Contexto de los umbrales de P3 | ⏳ Sin confirmar con fuente oficial |
| E4 | Informalidad laboral (DANE, GEIH) | Límite de la lectura demográfica del soporte | ⏳ No descargada |
| E5 | Natural Earth, fronteras de países | Mapas y análisis espacial (scripts 04 a 06) | ✅ En uso |
| E6 | Indicadores económicos (Banco Mundial) | Validar tipologías con una dimensión externa | ⬜ Opcional, no usada |

------------------------------------------------------------------------

## 2. Detalle

### E0 · Archivos entregados por el concurso (ONU, WPP 2024)

| Campo | Valor |
|----|----|
| Fuente | United Nations, Department of Economic and Social Affairs, Population Division (2024). *World Population Prospects 2024, Online Edition* |
| Archivos locales | `data/raw/WPP2024_Demographic_Indicators_Medium_csv.gz`, `..._OtherVariants_csv.gz`, `..._notes.csv`, `WPP2024_Supplement_Births_and_LE60.csv` |
| URL | **[COMPLETAR]** (los entregó el concurso; la fuente primaria es <https://population.un.org/wpp/>) |
| Fecha de descarga | **[COMPLETAR]** |
| Licencia | Creative Commons CC BY 3.0 IGO (requiere atribución) |
| Transformaciones | Países = `ISO3_code` no nulo (D1); años 1950-2100 (D3); suplemento unido por `LocID` y `Time`; sin imputación (D6). Resultado: `data/clean/wpp_paises_medium_suppl.parquet` |
| Notas | El suplemento no incluye Holy See (D4). Las 5 variables del suplemento no están en Medium (guía del concurso) |

### E1 · ONU, WPP 2024: población por edad simple y sexo

| Campo | Valor |
|----|----|
| Fuente | UN Population Division, WPP 2024, *Population by single age and sex*, variante Medium |
| Archivos locales | `data/raw/externos/WPP2024_PopulationBySingleAgeSex_Medium_1950-2023.csv` y `..._Medium_2024-2100.csv` (con o sin `.gz`), población a **1 de julio** (D19) |
| Otros archivos descargados | Población a 1 de enero (1950-2023 y 2024-2100); no se usa en el análisis principal |
| URL | <https://population.un.org/wpp/downloads> (página de descargas) · **[COMPLETAR]** enlace directo a cada archivo |
| Fecha de descarga | **[COMPLETAR]** |
| Licencia | CC BY 3.0 IGO |
| Transformaciones | Filtro `Variant = 'Medium'` y `LocID` presente en la tabla maestra; suma por grandes grupos de edad (0-14, 15-59, 15-64, 60+, 65+); mediana calculada con interpolación dentro de la edad simple (D21). Resultado: `data/clean/un_estructura_edad.parquet` |
| Validación | La suma por edades reproduce `TPopulation1July` (diferencia relativa máxima de 1.5e-5 en el universo; 2.2 % en Holy See). La mediana calculada supera a `MedianAgePop` en 1.00 año (D21) |
| Pendiente | Variantes Low y High de población por edad (plan §5, E1): **no descargadas / no usadas** hasta la Fase 3 |

### E2 · DANE: proyecciones nacionales de población por área, sexo y edad (PPED)

| Campo | Archivo 1950-2017 | Archivo 2018-2070 |
|----|----|----|
| Archivo local | `data/raw/externos/PPED-AreaSexoEdadNac-1950-2017.xlsx` | `data/raw/externos/PPED-AreaSexoEdadNac-2018-2070.xlsx` |
| Hoja de datos | `Nacional_1950_2017` | `PobNacionalxÁreaSexoEdad` (`Índice` y `PPED` son documentación) |
| Versión declarada | "Actualización: Marzo de 2023" (pie de la hoja) | "Actualizado el 18 de Julio de 2025" (hoja `PPED`) |
| Estructura | Encabezado de una fila (DP, DPNOM, AÑO, ÁREA GEOGRÁFICA, `Hombres_0`…); 3 filas por año (Cabecera, Centros Poblados y Rural Disperso, Total); pies de nota | Encabezado de dos filas (AÑO en la fila 8, nombres por edad en la fila 9); columnas Total, Hombres, Mujeres; 202 columnas por edad y sexo |
| URL | **[COMPLETAR]** (sugerida en el plan: <https://www.dane.gov.co/estadisticas-por-tema/demografia-y-poblacion/proyecciones-de-poblacion>) | **[COMPLETAR]** |
| Fecha de descarga | **[COMPLETAR]** | **[COMPLETAR]** |
| Licencia / términos de uso | **[COMPLETAR]** (verificar en el sitio del DANE) | **[COMPLETAR]** |

**Transformaciones (script 03):** lectura de la hoja completa como texto y localización del encabezado; filtro Área = Total (sin él la población se triplica); paso de formato ancho a largo; 202 columnas por edad y sexo; empalme de los dos archivos (el año 2018 sale del archivo 2018-2070). Resultado: `data/clean/dane_estructura_edad.rds`.

**Validación y límites (D20, D25, D27):** - Puntos de control del PDF de marzo de 2023: 14 de 14 en 1950-2017; 3 de 24 en 2018-2070 (versiones distintas). - Verificación interna del Excel 2018-2070: suma de las 202 edades frente a la columna Total (**pendiente de confirmar al re-ejecutar el 03**). - Ruptura del empalme 2017 → 2018: el crecimiento pasa de 1.26 % a 1.77 % (D25). El análisis de soporte (P3) usa solo 2018-2070. - En la figura del script 03 se observa otra inflexión en la serie histórica hacia 1985. **No investigada**; podría estar ligada a la reconstrucción con el censo de ese año (hipótesis sin verificar).

### E2-doc · DANE: documentación y puntos de control

| Campo | Valor |
|----|----|
| Documento | Presentación "Proyecciones de población: indicadores demográficos", marzo de 2023 |
| Ubicación | `data/raw/externos/documentacion/` |
| Tabla de control | `data/raw/externos/documentacion/checkpoints_dane.csv` (59 filas; columnas: indicador, año, serie, valor, tolerancia, tipo de tolerancia, unidad, fuente, nota). El script 03 usa las 38 filas con `serie = "post"` |
| URL y fecha de descarga | **[COMPLETAR]** |
| Uso | Documentación y validación del tramo histórico. **No es dato de análisis** (D13) |
| Nota | Las curvas "WPP" del PDF corresponden a una revisión anterior de la ONU y no se reutilizan (D20) |

### E3 · Parámetros pensionales de Colombia

| Campo | Valor |
|----|----|
| Qué es | Edades de jubilación (57 mujeres y 62 hombres), cotización (16 %), Ley 2381 de 2024 |
| Origen actual | Verificado en prensa. **Sin confirmar con fuente oficial** |
| URL | **[COMPLETAR]** (norma oficial, p. ej. el texto de la Ley 2381 de 2024 en el sitio de la Presidencia o del Congreso) |
| Fecha de consulta | **[COMPLETAR]** |
| Uso | Solo contexto y escenarios de sensibilidad de los umbrales de P3; **no se modela** (plan §9) |
| Estado | ⏳ No citar en el reporte hasta confirmar |

### E4 · Informalidad laboral en Colombia (DANE, GEIH)

| Campo | Valor |
|----|----|
| Qué es | Serie oficial de informalidad laboral (Gran Encuesta Integrada de Hogares) |
| Uso previsto | Límite de la lectura demográfica del soporte: el PSR no mide sostenibilidad pensional |
| URL, fecha, licencia | **[COMPLETAR]** |
| Estado | ⏳ No descargada. Si no se descarga, la limitación se redacta sin cifras |

### E5 · Natural Earth: fronteras de países

| Campo | Valor |
|----|----|
| Fuente | Natural Earth, *Admin 0 - Countries*, escala 1:50m |
| Acceso | Paquetes de R `rnaturalearth` 1.2.0 y `rnaturalearthdata` 1.0.0, consultados el **2026-10-28** |
| Copia local | `data/raw/externos/natural_earth_admin0_50m.gpkg` (la genera el script 04) |
| URL | <https://www.naturalearthdata.com> |
| Licencia | El proveedor la declara de dominio público. **[COMPLETAR]** confirmar en <https://www.naturalearthdata.com/about/terms-of-use/> antes de citar |
| Transformaciones (D22) | Sin Antártida; ISO3 con `iso_a3`, completado con `iso_a3_eh` y `adm0_a3`; `AUS` disuelto; reparación de geometrías sin s2 y partición en el antimeridiano; recodificación `KOS` → `XKX`. Resultado: `data/clean/mundo_geom.rds` y `mundo_puntos.rds` |
| Cobertura | 229 de 237 países/áreas de WPP con polígono; 161 de 161 del universo. Sin polígono: Reunión, Guadalupe, Martinica, Mayotte y Guayana Francesa (parte de Francia en Natural Earth), Gibraltar, Bonaire-San Eustaquio-Saba y Tokelau |
| Aviso en mapas | Las fronteras son ilustrativas y no implican reconocimiento oficial alguno |

### E6 · Indicadores económicos (Banco Mundial)

Opcional; **no usada**. Si se incorpora: unión por `ISO3_code`, registro completo aquí antes de usarse y declarar que es una dimensión externa de validación de la tipología (plan §5).

------------------------------------------------------------------------

## 3. Citas sugeridas

-   United Nations, Department of Economic and Social Affairs, Population Division (2024). *World Population Prospects 2024, Online Edition.* Licencia CC BY 3.0 IGO.
-   DANE, Dirección de Censos y Demografía. *Proyecciones de población nacionales por área, sexo y edad (PPED)*: archivo 1950-2017 (actualización de marzo de 2023) y archivo 2018-2070 (actualizado el 18 de julio de 2025).
-   Natural Earth. *Admin 0 - Countries*, 1:50m, vía `rnaturalearth` 1.2.0 y `rnaturalearthdata` 1.0.0 (consultados el 28-oct-2026).
-   American Statistical Association (2022). *Ethical Guidelines for Statistical Practice.* <https://doi.org/10.5281/zenodo.7092386>

## 4. Lista de pendientes de este archivo

-   [ ] URL exacta y fecha de descarga de E0, E1, E2 y E2-doc.
-   [ ] Términos de uso del DANE (E2).
-   [ ] Confirmar la licencia de Natural Earth (E5).
-   [ ] Confirmar con fuente oficial los parámetros pensionales (E3), o dejarlos fuera del reporte.
-   [ ] Decidir si se descarga la informalidad (E4).
-   [ ] Re-ejecutar el 03 y anotar el resultado de la verificación interna del Excel 2018-2070.
