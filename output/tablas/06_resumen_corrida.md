### Corrida del 2026-10-29 06:32

- Universo espacial: 161 países; k = 5; semilla 2026.
- Permutaciones: Moran global 999, serie 199, LISA 4999.
- Vecinos más cercanos de Colombia: Costa Rica, Ecuador, Panama, Trinidad and Tobago, Venezuela (Bolivarian Republic of).

**Moran global** (p = piso con las permutaciones usadas, no un valor estimado):

| variable | anio | n | I | esperado | p_perm | tipo |
|---|---|---|---|---|---|---|
| edad_mediana | 2023 | 161 | 0.738 | -0.006 | 0.002 | estimación |
| edad_mediana | 2050 | 161 | 0.707 | -0.006 | 0.002 | proyección |
| edad_mediana | 2100 | 161 | 0.651 | -0.006 | 0.002 | proyección |
| tfr | 2023 | 161 | 0.705 | -0.006 | 0.002 | estimación |
| tfr | 2050 | 161 | 0.685 | -0.006 | 0.002 | proyección |
| tfr | 2100 | 161 | 0.612 | -0.006 | 0.002 | proyección |
| lex | 2023 | 161 | 0.687 | -0.006 | 0.002 | estimación |
| lex | 2050 | 161 | 0.69 | -0.006 | 0.002 | proyección |
| lex | 2100 | 161 | 0.68 | -0.006 | 0.002 | proyección |
| max_gan10_decada |  | 161 | 0.353 | -0.006 | 0.002 | proyección |

**Sensibilidad a k** (edad mediana; LISA significativos tras FDR):

| k | anio | I | p_perm | n_lisa_significativos |
|---|---|---|---|---|
| 3 | 2023 | 0.757 | 0.004 | 0 |
| 3 | 2050 | 0.719 | 0.004 | 0 |
| 3 | 2100 | 0.666 | 0.004 | 0 |
| 5 | 2023 | 0.738 | 0.004 | 72 |
| 5 | 2050 | 0.707 | 0.004 | 62 |
| 5 | 2100 | 0.651 | 0.004 | 42 |
| 8 | 2023 | 0.732 | 0.004 | 83 |
| 8 | 2050 | 0.707 | 0.004 | 82 |
| 8 | 2100 | 0.653 | 0.004 | 83 |

**Estabilidad Monte Carlo del conteo LISA** (k = 5, 3 semillas):

| anio | semillas | minimo | maximo |
|---|---|---|---|
| 2023 | 3 | 72 | 73 |
| 2050 | 3 | 61 | 62 |
| 2100 | 3 | 37 | 49 |

**Grupos LISA** (BH dentro de cada variable-año):

| variable | anio | Alto-Alto | Bajo-Bajo | Alto-Bajo | Bajo-Alto | No significativo |
|---|---|---|---|---|---|---|
| edad_mediana | 2023 | 34 | 37 | 1 | 0 | 89 |
| edad_mediana | 2050 | 25 | 36 | 1 | 0 | 99 |
| edad_mediana | 2100 | 9 | 31 | 1 | 1 | 119 |
| max_gan10_decada |  | 0 | 2 | 1 | 1 | 157 |

**Colombia:**

| variable | anio | valor | rezago_z | p | p_fdr | grupo |
|---|---|---|---|---|---|---|
| edad_mediana | 2023 | 31.6 | 0.18 | 0.686 | 0.855 | No significativo |
| edad_mediana | 2050 | 43.7 | 0.47 | 0.309 | 0.465 | No significativo |
| edad_mediana | 2100 | 51.8 | 0.7 | 0.11 | 0.206 | No significativo |
| max_gan10_decada |  | 4.7 | 0.81 | 0.076 | 0.29 | No significativo |

**Grupo LISA de la edad mediana, 2023 frente a 2100** (países):

| g2023 | g2100 | paises |
|---|---|---|
| Alto-Alto | Alto-Alto | 5 |
| Alto-Alto | No significativo | 29 |
| Bajo-Bajo | Bajo-Bajo | 26 |
| Bajo-Bajo | No significativo | 11 |
| Alto-Bajo | Alto-Bajo | 1 |
| No significativo | Alto-Alto | 4 |
| No significativo | Bajo-Bajo | 5 |
| No significativo | Bajo-Alto | 1 |
| No significativo | No significativo | 79 |

**Moran global por año** (años clave):

| anio | edad_mediana | tfr | lex |
|---|---|---|---|
| 1950 | 0.685 | 0.627 | 0.539 |
| 1975 | 0.721 | 0.662 | 0.534 |
| 2000 | 0.712 | 0.695 | 0.778 |
| 2023 | 0.738 | 0.705 | 0.687 |
| 2050 | 0.707 | 0.685 | 0.69 |
| 2075 | 0.658 | 0.655 | 0.685 |
| 2100 | 0.651 | 0.612 | 0.68 |

