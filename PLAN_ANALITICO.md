# Plan analítico previo · ASA DataQuest 2026

**Pasos 5 y 6 del plan.** Se redacta **antes** de modelar (principios B3 y C3 de la ASA): qué se pregunta, qué es exploratorio y qué confirmatorio, qué datos externos se incorporan y con qué reglas se decide. Cualquier cambio posterior se registra en `DECISIONES.md`, no se hace en silencio.

Fecha: 2026-10-20 · Insumos: Fase 0 (`scripts/00`), verificación de viabilidad (`scripts/01`), propuesta del equipo (PDF).

---

## 1. Pregunta central

> **¿Qué tan rápido, y con cuánta incertidumbre, envejecerá Colombia hasta 2100 en comparación con el mundo? ¿Qué arquetipos de envejecimiento existen entre países? ¿Qué tan sólida es la proyección oficial?**

| Subpregunta | Qué responde | Nombre en el reporte |
|---|---|---|
| **P1 · Arquetipos** | ¿Qué trayectorias de fecundidad, longevidad y estructura por edad agrupan a los países, y en qué año cambia Colombia de grupo? | Arquetipos de envejecimiento |
| **P2 · Incertidumbre y validación** | ¿Cuánta incertidumbre trae la propia proyección oficial, y qué tan bien pronostican métodos simples a 5-25 años? | Qué tan confiable es el futuro proyectado |
| **P3 · Soporte** | ¿Cuándo baja en Colombia la relación de soporte (15-64 / 65+) de umbrales de referencia, y cómo se compara ONU frente a DANE? | Puntos de inflexión del soporte demográfico |

**Alcance.** El análisis describe y compara proyecciones. No evalúa la sostenibilidad fiscal de ningún sistema pensional (ver punto 9).

---

## 2. Lo ya observado (exploratorio, *post hoc*)

Estos hallazgos salieron de la verificación de viabilidad. **No son hipótesis previas**: se reportan como descriptivos.

| Hallazgo (variante Medium) | Valor |
|---|---|
| Edad mediana de Colombia | 16.9 (1950) → 31.6 (2023) → 43.7 (2050) → 51.8 (2100) |
| Velocidad de envejecimiento de Colombia | Máximo de **+4.7 años por década en 2040**; baja a +0.3 hacia 2100 |
| Índice vital (Births / Deaths) de Colombia | 2.50 en 2023; primer año con Births < Deaths: **2051** |
| Países con Births < Deaths | 53 de 237 (2023) → 106 (2050) → 164 (2100) |
| Efecto de la migración sobre la edad mediana de Colombia | Prácticamente nulo (43.9 frente a 43.7 en 2050; 51.8 en ambas en 2100) |
| Incertidumbre oficial (banda del 80 %) en la edad mediana de Colombia | Ancho de 4.7 años en 2050 y **12.4 años en 2100** |
| Banda del 95 % | Ancho de 7.6 años (2050) y 21.9 años (2100) |

Dos advertencias que condicionan el diseño:
- El ranking de velocidad de envejecimiento lo dominan territorios muy pequeños (Saint Martin, Cook Islands, Maldivas…). Se necesita un **universo de análisis** (D12).
- En los intervalos de la ONU, "Lower" produce una edad mediana **mayor** que "Upper" (46.2 frente a 41.5 en 2050). Las etiquetas no siguen el orden numérico del indicador; se verifica en el script 02 y se define la banda como [mínimo, máximo] del par (D14).

---

## 3. Universo de análisis (D9, D12)

- **Descriptivo:** los 237 países y áreas (ISO3).
- **Clustering, rankings y autocorrelación espacial:** solo países con población ≥ 1 millón en 2023 (propuesta; el umbral se fija con el conteo del script 02).
- **Ponderación:** peso igual por país para arquetipos; ponderado por población para cifras globales.
- Holy See queda fuera de todo análisis con suplemento (D4).

---

## 4. Variables y métricas

| Métrica | Definición | Fuente | Nota |
|---|---|---|---|
| Edad mediana | `MedianAgePop` | Medium | — |
| Velocidad de envejecimiento | Ganancia de `MedianAgePop` en 10 años (diferencia finita) | Derivada | Completa para 237 países |
| Fecundidad | `TFR`, `NRR` | Medium | `NRR` es el reemplazo generacional demográfico |
| Longevidad | `LEx`, `LE60`, `LE65` | Medium + suplemento | `LE60` excluye Holy See |
| **Índice vital** | `Births / Deaths` | Derivada | Antes llamado "reemplazo generacional" en la propuesta; se renombra |
| **Soporte potencial (PSR)** | Población 15-64 / población 65+ | **Externa (ONU por edad)** | No se puede calcular con los 4 archivos entregados |

Selección final de indicadores del PCA (D10): se decide con la matriz de correlación de la Fase 2, evitando redundancia (`LEx` con `LExMale`/`LExFemale`, `Births` con `CBR`) y excluyendo `DoublingTime`.

---

## 5. Datos externos (D13)

El concurso incentiva complementar con otras fuentes. **Regla del proyecto:** toda fuente externa se registra en `data/raw/externos/FUENTES.md` (qué es, URL, fecha de descarga, licencia, transformaciones) antes de usarse.

| # | Fuente | Qué aporta | Uso | Estado |
|---|---|---|---|---|
| E1 | ONU WPP 2024, población por edad simple y sexo (escenarios Medium, Low, High; 2024-2100) | Población 15-64 y 65+ para PSR | P3, validación cruzada de `MedianAgePop` | ✅ Descargados: 1 de julio 1950-2023, 1 de enero 1950-2023 y 1 de enero 2024-2100. **Falta** el de 1 de julio 2024-2100 (D19) |
| E2 | DANE, proyecciones nacionales de población 1950-2070 por sexo y edad (actualización posterior a la pandemia) | Segunda proyección oficial de Colombia | P3: ONU frente a DANE | ✅ Descargados y cargados (formato ancho; filtrar Área = Total). Versión por verificar con los puntos de control del PDF (D20) |
| E2-doc | DANE, presentación "Proyecciones de población: indicadores demográficos" (marzo de 2023) | Contexto metodológico y puntos de control | Documentación, no dato (D20) | ✅ En `data/raw/externos/documentacion/` |
| E3 | Parámetros pensionales de Colombia (edades de jubilación 57 mujeres / 62 hombres, cotización 16 %; Ley 2381 de 2024) | Contexto para los umbrales de P3 | Solo contexto y escenarios de sensibilidad | ✅ Verificado en prensa; **confirmar con fuente oficial** |
| E4 | Informalidad laboral en Colombia (DANE, GEIH) | Límite de la lectura demográfica del soporte | Contexto en limitaciones | ⏳ Consultar serie oficial |
| E5 | Fronteras mundiales (Natural Earth vía `rnaturalearth`) | Mapas y análisis espacial | Fase espacial (ampliación) | ⏳ Verificar licencia y campo ISO3 |
| E6 | Indicadores económicos (Banco Mundial) | Validar la tipología con una dimensión externa | Ampliación | Opcional |

**Reglas de uso:**
- Unión siempre por `ISO3_code`; los países sin correspondencia se listan y se documentan (B1).
- Ningún dato externo sustituye a Medium en la comparación principal: es insumo o contraste.
- Se citan todas las fuentes con licencia y fecha de acceso.

---

## 6. Métodos

### 6.1 Arquetipos (P1)

1. Indicadores estandarizados por país-año (1950-2100) en un **espacio PCA único**, ajustado con todo el panel.
2. Clustering (k-means y jerárquico) sobre las puntuaciones PCA de **país-año**, no sobre la trayectoria completa. Así, cada país puede cambiar de grupo con el tiempo.
3. Elección de *k*: silueta, estabilidad por remuestreo y sentido sustantivo.
4. **Regla de transición (D15):** un país "pasa" al grupo B en el primer año a partir del cual permanece en B **al menos 5 años consecutivos**. Sensibilidad con 3 y 10 años. Se reporta con rango, no como "año exacto".
5. Los arquetipos describen **el escenario Medium de la ONU**, no datos observados (por eso se separa estimación de proyección).

### 6.2 Incertidumbre y validación (P2)

1. **Banda oficial:** para `MedianAgePop`, `TFR`, `LEx` y población, usar los intervalos del 80 % y 95 % (D14).
2. **Pronóstico propio, validado dentro de 1950-2023:** ventana móvil (*rolling origin*) con horizontes de 5, 10 y 20 años.
   - Líneas base obligatorias: ingenuo y deriva.
   - Modelos: ETS/ARIMA con tendencia amortiguada y un modelo de panel (GAM) para el cambio de TFR y LEx.
   - Métricas: MAE y RMSE por horizonte, y cobertura de los intervalos.
3. **Ampliación opcional:** XGBoost sobre **cambios** (los árboles no extrapolan niveles fuera del rango visto).
4. **Descartados por ahora:** Prophet (sin estacionalidad que justifique) y LSTM (pocos datos efectivos por país).
5. **Discrepancia con la ONU (D16):** un pronóstico propio "discrepa" solo si cae **fuera de la banda del 80 %** oficial. Dentro de ella, es consistente con la proyección oficial.
6. **Horizonte:** lo validable llega a ~20-25 años. La extrapolación a 2100 se presenta solo como ejercicio ilustrativo, con intervalos.

### 6.3 Soporte demográfico (P3)

1. PSR = población 15-64 / población 65+ (E1), para Medium, High y Low.
2. Umbrales de referencia **3.0 y 2.5**, declarados ahora como escenarios (no estándares), con sensibilidad a 2.0 y 4.0.
3. **Año de cruce:** primer año en que PSR queda por debajo del umbral **al menos 3 años seguidos**. Se reporta como rango entre variantes.
4. Comparación ONU frente a DANE hasta 2070 (horizonte del DANE).
5. El PSR es un indicador demográfico: **no equivale a la sostenibilidad de un sistema pensional** (ver punto 9).

### 6.4 Migración

No se excluye de las variables (están afectadas por ella en las proyecciones). Su efecto se **cuantifica** comparando Medium con `Zero migration` (D17). Para Colombia el efecto sobre la edad mediana es casi nulo; se verifica para el resto de países.

### 6.5 Autocorrelación espacial (ampliación)

- Moran global y local sobre variables **continuas** (edad mediana, velocidad de envejecimiento), no sobre etiquetas de clúster (para esas, estadísticos de conteo de uniones).
- Pesos por k vecinos más cercanos (hay islas sin vecinos).
- LISA con corrección por pruebas múltiples (FDR).
- Países sin polígono: se listan y se excluyen (B1).

---

## 7. Exploratorio frente a confirmatorio

| Análisis | Tipo | Comparaciones |
|---|---|---|
| EDA, correlaciones, velocidad de envejecimiento | Exploratorio | No se hacen pruebas de hipótesis |
| PCA y clustering | Exploratorio | Elección de *k* documentada |
| Validación de pronósticos (horizontes 5/10/20) | **Confirmatorio** | 3 horizontes x 3 indicadores x modelos, definidos aquí; reportar todos |
| Cruce de umbrales de PSR | Descriptivo con sensibilidad | Umbrales declarados en este documento |
| LISA | Exploratorio | Corrección FDR |

---

## 8. Orden de trabajo y criterios de cierre

| Orden | Entregable | Criterio de cierre |
|---|---|---|
| 1 | Script 02: universo, orden de etiquetas PI, efecto de migración en todos los países | Umbral de universo y D14 y D17 confirmados |
| 2 | Descarga y registro de E1 y E2 (`FUENTES.md`) | PSR de Colombia calculado para Medium y reproducido de forma independiente con los datos del DANE |
| 3 | EDA (Fase 2) | 6-8 figuras y lista de hallazgos |
| 4 | Features, PCA y clustering país-año | *k* justificado, transición de Colombia con rango |
| 5 | Validación de pronósticos y banda oficial | Tabla de error por horizonte y cobertura |
| 6 | Soporte demográfico (P3) | Años de cruce con rango y sensibilidad |
| 7 | Reporte Rmd y Shiny | Revisión externa (Paso 24) |
| 8 | Ampliaciones (XGBoost, mapas y Moran) | Solo si 1-7 están cerrados |

Reparto sugerido (propuesta del equipo): **Predictivo** (orden 5), **Clustering** (orden 4), **Espacial y visualización** (orden 8 y mapas de P1).

---

## 9. Lo que este proyecto NO afirmará

- Que el pronóstico propio sea "mejor" o "peor" que el de la ONU a 2100: no existe verdad observable para validarlo.
- Un "año exacto" de transición o de cruce: siempre con rango y sensibilidad.
- Que el PSR por debajo de 3 o 2.5 implique insolvencia: depende de informalidad, edad de retiro, densidad de cotización y diseño del sistema, que no están en el dato demográfico. La reforma pensional colombiana (Ley 2381 de 2024) se cita como contexto, no se modela.
- Que los arquetipos sean observaciones: describen la proyección oficial.
- Nombres estigmatizantes para grupos de países (principio D6 de las guías de la ASA): los arquetipos llevan nombres descriptivos.