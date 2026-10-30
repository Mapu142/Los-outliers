### EDA · corrida del 2026-10-30 08:52

- Universo: 161 países (>= 1 millón de habitantes en 2023). Todo es exploratorio.

**Reemplazo generacional** (% de países y de población bajo TFR 2,1):

| Time | pct_paises | pct_pob | pct_paises_nrr |
|---|---|---|---|
| 1950 | 1.2 | 0.4 | 2.5 |
| 1975 | 13 | 19.8 | 14.3 |
| 2000 | 36.6 | 46.1 | 36.6 |
| 2023 | 50.3 | 67.3 | 51.6 |
| 2050 | 67.1 | 69 | 67.1 |
| 2075 | 76.4 | 69 | 76.4 |
| 2100 | 93.2 | 87 | 92.5 |

- La mitad de los países baja del reemplazo en 2022; la mitad de la población, en 2020; Colombia, en 2009.

**Colombia, América Latina y el mundo** (edad mediana):

| serie | 1950 | 1975 | 2000 | 2023 | 2050 | 2075 | 2100 |
|---|---|---|---|---|---|---|---|
| Colombia | 16.9 | 16.7 | 23.2 | 31.6 | 43.7 | 50 | 51.8 |
| América Latina y el Caribe | 18.3 | 17.9 | 23.2 | 30.9 | 40.5 | 46.4 | 49.1 |
| Mundo | 22.2 | 20.7 | 25.1 | 30.4 | 36.1 | 39.5 | 42.1 |

**Primer año en que la edad mediana alcanza el umbral:**

| umbral | Colombia | América Latina y el Caribe | Mundo |
|---|---|---|---|
| 40 | 2042 | 2049 | 2080 |
| 50 | 2075 |  |  |

**Pares de indicadores con |rho de Spearman| >= 0.9** (evidencia para D10):

| a | b | rho | anio |
|---|---|---|---|
| TFR | NRR | 0.998 | 2023 |
| Mortalidad infantil | Mortalidad < 5 años | 0.997 | 2023 |
| Edad mediana | Tasa de natalidad | -0.977 | 2023 |
| Tasa de natalidad | Crecimiento natural | 0.977 | 2023 |
| TFR | Tasa de natalidad | 0.976 | 2023 |
| Edad mediana | Crecimiento natural | -0.975 | 2023 |
| NRR | Tasa de natalidad | 0.973 | 2023 |
| Esp. de vida al nacer | Esp. de vida a los 60 | 0.968 | 2023 |
| NRR | Crecimiento natural | 0.942 | 2023 |
| TFR | Crecimiento natural | 0.94 | 2023 |
| Esp. de vida al nacer | Mortalidad < 5 años | -0.934 | 2023 |
| TFR | Edad mediana | -0.932 | 2023 |
| Esp. de vida al nacer | Mortalidad infantil | -0.93 | 2023 |
| NRR | Edad mediana | -0.928 | 2023 |
| Crecimiento natural | Índice vital (log) | 0.923 | 2023 |
| Edad mediana | Mortalidad < 5 años | -0.92 | 2023 |
| Tasa de natalidad | Mortalidad < 5 años | 0.917 | 2023 |
| Edad mediana | Mortalidad infantil | -0.913 | 2023 |
| Tasa de natalidad | Mortalidad infantil | 0.911 | 2023 |
| Mortalidad infantil | Mortalidad < 5 años | 0.999 | 2050 |
| TFR | NRR | 0.997 | 2050 |
| Esp. de vida al nacer | Esp. de vida a los 60 | 0.99 | 2050 |
| Edad mediana | Tasa de natalidad | -0.99 | 2050 |
| Crecimiento natural | Crecimiento poblacional | 0.988 | 2050 |
| Edad mediana | Crecimiento natural | -0.981 | 2050 |
| TFR | Tasa de natalidad | 0.98 | 2050 |
| NRR | Tasa de natalidad | 0.977 | 2050 |
| Crecimiento natural | Índice vital (log) | 0.974 | 2050 |
| Tasa de natalidad | Crecimiento natural | 0.968 | 2050 |
| Crecimiento poblacional | Índice vital (log) | 0.965 | 2050 |
| Edad mediana | Crecimiento poblacional | -0.963 | 2050 |
| TFR | Edad mediana | -0.955 | 2050 |
| NRR | Edad mediana | -0.953 | 2050 |
| Tasa de natalidad | Crecimiento poblacional | 0.948 | 2050 |
| Tasa de mortalidad | Índice vital (log) | -0.947 | 2050 |
| Edad mediana | Índice vital (log) | -0.942 | 2050 |
| Esp. de vida al nacer | Mortalidad infantil | -0.934 | 2050 |
| Esp. de vida al nacer | Mortalidad < 5 años | -0.934 | 2050 |
| NRR | Crecimiento natural | 0.931 | 2050 |
| TFR | Crecimiento natural | 0.928 | 2050 |
| Esp. de vida a los 60 | Mortalidad infantil | -0.921 | 2050 |
| Esp. de vida a los 60 | Mortalidad < 5 años | -0.92 | 2050 |
| Tasa de natalidad | Índice vital (log) | 0.916 | 2050 |
| NRR | Crecimiento poblacional | 0.905 | 2050 |
| TFR | Crecimiento poblacional | 0.901 | 2050 |

**Años con más países en caída de la esperanza de vida** (>= 1 año):

| Time | n_leve | n_fuerte |
|---|---|---|
| 2021 | 52 | 20 |
| 2020 | 50 | 17 |
| 1992 | 9 | 3 |
| 1993 | 9 | 2 |
| 1998 | 9 | 3 |
| 1974 | 8 | 6 |
| 1990 | 8 | 2 |
| 1994 | 8 | 1 |

**Mayores caídas de la esperanza de vida (país-año):**

| Location | Time | d_lex | lex |
|---|---|---|---|
| Central African Republic | 2009 | -35.2 | 14.7 |
| Rwanda | 1994 | -30.8 | 12.2 |
| Cambodia | 1975 | -26.5 | 12.8 |
| Somalia | 1991 | -21.5 | 25.4 |
| Central African Republic | 2022 | -21.5 | 18.8 |
| Lebanon | 1976 | -21.3 | 36.4 |
| Central African Republic | 2019 | -20.8 | 31.5 |
| Bosnia and Herzegovina | 1992 | -19.8 | 52 |
| Burundi | 1972 | -17.4 | 25.8 |
| Somalia | 2011 | -16.4 | 32.5 |
| Bangladesh | 1971 | -16.1 | 26.5 |
| Haiti | 2010 | -16.1 | 45.6 |
| Armenia | 1988 | -14.9 | 52.7 |
| Cyprus | 1974 | -14.5 | 54.6 |
| South Sudan | 1998 | -14 | 19 |

**Mayores picos de migración neta (tasa por 1 000 hab. respecto a su mediana móvil):**

| Location | Time | cnmr | base | pico | migr_neta_miles |
|---|---|---|---|---|---|
| Kuwait | 1990 | -709.9 | 13.8 | -723.7 | -1196 |
| China, Hong Kong SAR | 1967 | -359.3 | 23.6 | -382.9 | -1248 |
| China, Hong Kong SAR | 1964 | 357.1 | 6.7 | 350.4 | 1120 |
| Kuwait | 1991 | 340.9 | 13.8 | 327.1 | 461 |
| Liberia | 1990 | -320.4 | 3.2 | -323.7 | -713 |
| Timor-Leste | 1999 | -315 | 2 | -317 | -263 |
| Rwanda | 1994 | -305.9 | -1.6 | -304.3 | -2078 |
| Rwanda | 1996 | 203.9 | -7.9 | 211.8 | 1368 |
| Eritrea | 1991 | -171.2 | -3.7 | -167.5 | -329 |
| Qatar | 2006 | 209.9 | 53 | 156.9 | 204 |
| Qatar | 2007 | 203.3 | 53 | 150.3 | 246 |
| Afghanistan | 1981 | -167.4 | -18.3 | -149.1 | -1998 |

- Colombia: máximo de migración neta estimada 496 (miles) en 2018; mínimo -98 en 1976.

