# 0. Parámetros y librerías -------------------------------------------

source("R/config.R", encoding = "UTF-8")
source("R/tema.R",   encoding = "UTF-8")

library(duckdb)
library(DBI)
library(dplyr)
library(tidyr)
library(ggplot2)
library(forecast)
library(mgcv)

H              <- 77          # Horizonte - años a pronosticar (2024-2100)
ANIO_FIN_HIST  <- 2023
ORIGENES       <- c(1990, 2000, 2010)      # orígenes del backtesting
PAIS_FOCO      <- "COL"
POB_VARIANTE   <- "Median"
UMBRAL_RS      <- 3        # trabajadores activos por pensionado

# Territorios excluidos por población mínima y datos incompletos:
#  - VAT (Vaticano): sin LE60.
#  - NRU (Nauru): ~12 mil personas y no viene en el archivo de población por edad.
EXCLUIR_PAISES <- c("VAT", "NRU")

COL_VARIANT    <- "Variant"   
VARIANTE_ONU   <- "Medium"

# El COVID (2020-2021) contamina la "tendencia reciente" con la que arranca
# la proyección. Para ENTRENAR y arrancar el pronóstico se reemplazan esos
# años por una interpolación lineal; el histórico graficado sigue siendo el real.
ANIOS_COVID <- c(2020, 2021)
VARS_COVID  <- c("LEx", "LE60", "LE65", "IRG")

PROP_EXCLUIR_CHOQUES <- 0.10

VARS_CORE  <- c("MedianAgePop", "TFR", "LEx")
VARS_EXTRA <- c("LE60", "LE65", "CBR", "IRG", "RS")   # IRG = Births / Deaths

LIMITES <- list(
  MedianAgePop = c(10, 60),
  TFR          = c(0.8, 8),
  LEx          = c(30, 100),
  LE60         = c(3, 40),
  LE65         = c(2, 35),
  CBR          = c(2, 60),
  IRG          = c(0.05, 10),
  RS           = c(0.3, 30)
)

dir_out <- if (!is.null(CFG$dir_out)) CFG$dir_out else "R/time series"
dir.create(dir_out, showWarnings = FALSE, recursive = TRUE)
out <- function(f) file.path(dir_out, f)


#Métodos para pronósticos
METODO_FINAL   <- "Ensamble"
stopifnot(METODO_FINAL %in% c("Ensamble", "ETS", "GAM", "Estructural"))

# Método por variable, elegido con resumen_validacion.csv.
METODOS_POR_VARIABLE <- c(MedianAgePop = "Estructural", TFR = "Ensamble", LEx = "Ensamble",
                          LE60 = "GAM", LE65 = "GAM", CBR = "GAM", IRG = "ETS",
                          RS = "Ensamble")  


# 1. Datos ------------------------------------------------------------

#conexion con la base de datos
con <- dbConnect(duckdb::duckdb()) 
ruta_parquet <- file.path(CFG$dir_clean, CFG$f_parquet)
dbExecute(con, sprintf(
  "CREATE OR REPLACE VIEW wpp AS SELECT * FROM read_parquet('%s')", ruta_parquet
))
cols <- dbListFields(con, "wpp")

faltan <- setdiff(c("ISO3_code", "Time", VARS_CORE), cols)
if (length(faltan) > 0) stop("Faltan columnas en el parquet: ", paste(faltan, collapse = ", "))

if (COL_VARIANT %in% cols) {
  filtro_var <- sprintf("AND \"%s\" = '%s'", COL_VARIANT, VARIANTE_ONU)
} else {
  filtro_var <- ""
  message("No hay columna '", COL_VARIANT, "': se asume una sola variante en las proyecciones.")
}

datos_hist <- dbGetQuery(con, sprintf("
  SELECT * FROM wpp
  WHERE ISO3_code IS NOT NULL AND TRIM(ISO3_code) <> '' AND Time <= %d
  ORDER BY ISO3_code, Time", as.integer(ANIO_FIN_HIST)))

datos_onu <- dbGetQuery(con, sprintf("
  SELECT * FROM wpp
  WHERE ISO3_code IS NOT NULL AND TRIM(ISO3_code) <> '' AND Time > %d %s
  ORDER BY ISO3_code, Time", as.integer(ANIO_FIN_HIST), filtro_var))

if (anyDuplicated(datos_onu[c("ISO3_code", "Time")]) > 0) {
  stop("Proyecciones ONU duplicadas por (país, año): revisa el filtro de variante.")
}

agregar_irg <- function(df) {
  if (all(c("Births", "Deaths") %in% names(df))) {
    df$IRG <- df$Births / df$Deaths
    df$IRG[!is.finite(df$IRG)] <- NA
  }
  df
}
datos_hist <- agregar_irg(datos_hist)
datos_onu  <- agregar_irg(datos_onu)

# Relación de soporte desde el CSV de población por edad (formato largo de la ONU)
leer_relacion_soporte <- function(ruta) {
  primera <- readLines(ruta, n = 1, warn = FALSE)
  sep <- if (grepl("\t", primera)) "\t" else if (grepl(";", primera)) ";" else ","
  d0 <- readr::read_delim(ruta, delim = sep, na = c("", "NA", "null"),
                          col_types = readr::cols(.default = "c"),
                          show_col_types = FALSE, progress = FALSE)
  d <- d0 %>% filter(Variant == POB_VARIANTE, Sex == "Both sexes", Age %in% c("15-64", "65+"))
  if (nrow(d) == 0) {
    stop("Sin filas con Variant = '", POB_VARIANTE, "', Sex = 'Both sexes' y Age = 15-64 / 65+. ",
         "Variantes disponibles: ", paste(unique(d0$Variant), collapse = ", "))
  }
  d %>%
    transmute(ISO3_code = Iso3, Time = as.integer(Time), Age, Value = as.numeric(Value)) %>%
    distinct(ISO3_code, Time, Age, .keep_all = TRUE) %>%
    pivot_wider(names_from = Age, values_from = Value) %>%
    transmute(ISO3_code, Time, RS = ifelse(`65+` > 0, `15-64` / `65+`, NA_real_))
}

RUTA_POB_EDAD  <- "R/time series/poblacion_por_edad.csv"

if (file.exists(RUTA_POB_EDAD)) {
  rs_tab     <- leer_relacion_soporte(RUTA_POB_EDAD)
  datos_hist <- datos_hist %>% left_join(rs_tab, by = c("ISO3_code", "Time"))
  datos_onu  <- datos_onu  %>% left_join(rs_tab, by = c("ISO3_code", "Time"))
  cat("Relación de soporte cargada desde", RUTA_POB_EDAD, "\n")
} else {
  message("No se encontró '", RUTA_POB_EDAD, "': se omite la relación de soporte (RS).")
}

VARS <- intersect(c(VARS_CORE, VARS_EXTRA), names(datos_hist))
stopifnot(all(VARS %in% names(LIMITES)))
cat("Variables a proyectar:", paste(VARS, collapse = ", "), "\n")

# Matrices países x años (una por variable)
hacer_matriz <- function(df, v) {
  w <- df %>%
    select(ISO3_code, Time, all_of(v)) %>%
    pivot_wider(names_from = Time, values_from = all_of(v)) %>%
    arrange(ISO3_code)
  m <- as.matrix(w[, -1])
  rownames(m) <- w$ISO3_code
  m[, order(as.numeric(colnames(m))), drop = FALSE]
}

M_hist <- lapply(setNames(VARS, VARS), function(v) hacer_matriz(datos_hist, v))
paises <- setdiff(rownames(M_hist[[1]]), EXCLUIR_PAISES)
M_hist <- lapply(M_hist, function(m) m[paises, , drop = FALSE])

con_na <- names(M_hist)[vapply(M_hist, anyNA, logical(1))]
if (length(intersect(con_na, VARS_CORE)) > 0) {
  stop("Hay NA en variables centrales: ", paste(intersect(con_na, VARS_CORE), collapse = ", "))
}
if (length(con_na) > 0) {
  warning("Se descartan variables con NA: ", paste(con_na, collapse = ", "))
  for (v in con_na) {
    m <- M_hist[[v]]
    anios_na   <- as.integer(colnames(m))[colSums(is.na(m)) > 0]
    paises_na  <- names(which(rowSums(is.na(m)) > 0))
    cat("\nDiagnóstico de NA en", v, ":\n")
    cat("  años con NA:", length(anios_na), "(de", min(anios_na), "a", max(anios_na), ")\n")
    cat("  países con NA:", length(paises_na), "de", nrow(m), "\n")
    if (length(paises_na) < nrow(m)) print(head(paises_na, 20))
  }
  M_hist <- M_hist[setdiff(names(M_hist), con_na)]
  VARS   <- names(M_hist)
}

anios_hist <- as.integer(colnames(M_hist[[1]]))
anios_fut  <- (ANIO_FIN_HIST + 1):(ANIO_FIN_HIST + H)
stopifnot(max(anios_hist) == ANIO_FIN_HIST, all(diff(anios_hist) == 1))
cat("Países:", length(paises), "| años históricos:", length(anios_hist), "\n")

# Versión de los datos sin el efecto COVID (solo para modelar el pronóstico final)
ajustar_covid <- function(M, vars, anios_covid) {
  for (v in intersect(vars, names(M))) {
    m <- M[[v]]
    a <- as.integer(colnames(m))
    malos <- which(a %in% anios_covid)
    if (length(malos) == 0) next
    ref <- c(min(malos) - 1, max(malos) + 1)
    if (ref[1] < 1 || ref[2] > ncol(m)) next
    for (j in malos) {
      w <- (j - ref[1]) / (ref[2] - ref[1])
      m[, j] <- (1 - w) * m[, ref[1]] + w * m[, ref[2]]
    }
    M[[v]] <- m
  }
  M
}
M_modelo <- ajustar_covid(M_hist, VARS_COVID, ANIOS_COVID)

# 2. Modelos ----------------------------------------------------------

acotar <- function(nd, rangos) {
  for (nm in colnames(rangos)) nd[[nm]] <- pmin(pmax(nd[[nm]], rangos[1, nm]), rangos[2, nm])
  nd
}
acotar_m <- function(x, lim, n) {
  matrix(pmin(pmax(x, lim[1]), lim[2]), nrow = n)
}

# 2a. ETS con tendencia amortiguada, un modelo por país
proyectar_ets <- function(Y, h, lim) {
  res <- t(vapply(seq_len(nrow(Y)), function(i) {
    y <- ts(Y[i, ], start = 1, frequency = 1)
    tryCatch(as.numeric(forecast(ets(y, model = "AAN", damped = TRUE), h = h)$mean),
             error = function(e) rep(Y[i, ncol(Y)], h))
  }, numeric(h)))
  m <- acotar_m(res, lim, nrow(Y)); rownames(m) <- rownames(Y); m
}

# 2b. GAM global univariado: cambio anual ~ nivel + tendencia 5 y 15 años
entrenar_gam <- function(Y) {
  n <- ncol(Y)
  filas <- do.call(rbind, lapply(17:n, function(t) data.frame(
    nivel = as.numeric(Y[, t - 1]),
    mom5  = as.numeric(Y[, t - 1] - Y[, t - 6]) / 5,
    mom15 = as.numeric(Y[, t - 1] - Y[, t - 16]) / 15,
    delta = as.numeric(Y[, t] - Y[, t - 1])
  )))
  filas  <- filas[is.finite(rowSums(filas)), ]
  rangos <- sapply(filas[, c("nivel", "mom5", "mom15")], range)
  mod <- bam(delta ~ s(nivel, k = 8) + s(mom5, k = 6) + s(mom15, k = 6), data = filas)
  list(gam = mod, rangos = rangos, rd = range(filas$delta))
}

proyectar_gam <- function(Y, h, lim) {
  mod <- entrenar_gam(Y)
  n0  <- ncol(Y)
  Yf  <- cbind(Y, matrix(NA_real_, nrow(Y), h))
  for (k in seq_len(h)) {
    t  <- n0 + k
    nd <- data.frame(nivel = as.numeric(Yf[, t - 1]),
                     mom5  = as.numeric(Yf[, t - 1] - Yf[, t - 6]) / 5,
                     mom15 = as.numeric(Yf[, t - 1] - Yf[, t - 16]) / 15)
    d  <- as.numeric(predict(mod$gam, acotar(nd, mod$rangos)))
    d  <- pmin(pmax(d, mod$rd[1]), mod$rd[2])
    Yf[, t] <- pmin(pmax(Yf[, t - 1] + d, lim[1]), lim[2])
  }
  Yf[, (n0 + 1):(n0 + h), drop = FALSE]
}

# 2c. Modelo estructural para la edad mediana
proyectar_estructural <- function(MA, TFR, LEX, TFRfut, LEXfut, h, lim) {
  n0 <- ncol(MA); n <- nrow(MA)
  preds <- c("nivel", "mom5", "mom15", "tfr10", "tfr25", "lex")
  
  filas <- do.call(rbind, lapply(26:n0, function(t) data.frame(
    nivel = as.numeric(MA[, t - 1]),
    mom5  = as.numeric(MA[, t - 1] - MA[, t - 6]) / 5,
    mom15 = as.numeric(MA[, t - 1] - MA[, t - 16]) / 15,
    tfr10 = as.numeric(rowMeans(TFR[, (t - 10):(t - 1), drop = FALSE])),
    tfr25 = as.numeric(rowMeans(TFR[, (t - 25):(t - 1), drop = FALSE])),
    lex   = as.numeric(LEX[, t - 1]),
    delta = as.numeric(MA[, t] - MA[, t - 1])
  )))
  filas  <- filas[is.finite(rowSums(filas)), ]
  rangos <- sapply(filas[, preds], range)
  rd     <- range(filas$delta)
  mod <- bam(delta ~ s(nivel, k = 8) + s(mom5, k = 6) + s(mom15, k = 6) +
               s(tfr10, k = 6) + s(tfr25, k = 6) + s(lex, k = 6), data = filas)
  
  MAf <- cbind(MA,  matrix(NA_real_, n, h))
  TFf <- cbind(TFR, TFRfut)
  LEf <- cbind(LEX, LEXfut)
  for (k in seq_len(h)) {
    t  <- n0 + k
    nd <- data.frame(
      nivel = as.numeric(MAf[, t - 1]),
      mom5  = as.numeric(MAf[, t - 1] - MAf[, t - 6]) / 5,
      mom15 = as.numeric(MAf[, t - 1] - MAf[, t - 16]) / 15,
      tfr10 = as.numeric(rowMeans(TFf[, (t - 10):(t - 1), drop = FALSE])),
      tfr25 = as.numeric(rowMeans(TFf[, (t - 25):(t - 1), drop = FALSE])),
      lex   = as.numeric(LEf[, t - 1])
    )
    d <- as.numeric(predict(mod, acotar(nd, rangos)))
    d <- pmin(pmax(d, rd[1]), rd[2])
    MAf[, t] <- pmin(pmax(MAf[, t - 1] + d, lim[1]), lim[2])
  }
  res <- MAf[, (n0 + 1):(n0 + h), drop = FALSE]
  rownames(res) <- rownames(MA); res
}

# 2c-bis. Modelo estructural para la relación de soporte (RS)
# La RS cae a medida que la población envejece, así que su cambio anual (en
# logaritmo) se explica con el ritmo de aumento de la edad mediana proyectada
# (media de 5 años), el nivel de la edad mediana y el nivel de la propia RS.
proyectar_estructural_rs <- function(RS, MA, MAfut, h, lim) {
  n0  <- ncol(RS); n <- nrow(RS)
  L   <- log(RS)
  MAf <- cbind(MA, MAfut)        # edad mediana observada + proyectada (n x (n0 + h))
  
  filas <- do.call(rbind, lapply(6:n0, function(t) data.frame(
    nivel = as.numeric(L[, t - 1]),
    ma    = as.numeric(MAf[, t - 1]),
    dma5  = as.numeric(MAf[, t] - MAf[, t - 5]) / 5,
    delta = as.numeric(L[, t] - L[, t - 1])
  )))
  filas  <- filas[is.finite(rowSums(filas)), ]
  rangos <- sapply(filas[, c("nivel", "ma", "dma5")], range)
  rd     <- range(filas$delta)
  mod <- bam(delta ~ s(nivel, k = 8) + s(ma, k = 8) + s(dma5, k = 8), data = filas)
  
  Lf <- cbind(L, matrix(NA_real_, n, h))
  for (k in seq_len(h)) {
    t  <- n0 + k
    nd <- data.frame(nivel = as.numeric(Lf[, t - 1]),
                     ma    = as.numeric(MAf[, t - 1]),
                     dma5  = as.numeric(MAf[, t] - MAf[, t - 5]) / 5)
    d  <- as.numeric(predict(mod, acotar(nd, rangos)))
    d  <- pmin(pmax(d, rd[1]), rd[2])
    Lf[, t] <- pmin(pmax(Lf[, t - 1] + d, log(lim[1])), log(lim[2]))
  }
  res <- exp(Lf[, (n0 + 1):(n0 + h), drop = FALSE])
  rownames(res) <- rownames(RS); res
}

# 2d. Todos los métodos para todas las variables
proyectar_todo <- function(M, h) {
  out <- list()
  for (v in names(M)) {
    lim <- LIMITES[[v]]
    e <- proyectar_ets(M[[v]], h, lim)
    g <- proyectar_gam(M[[v]], h, lim)
    out[[v]] <- list(ETS = e, GAM = g, Ensamble = (e + g) / 2)
  }
  est <- proyectar_estructural(M$MedianAgePop, M$TFR, M$LEx,
                               out$TFR$Ensamble, out$LEx$Ensamble, h, LIMITES$MedianAgePop)
  out$MedianAgePop$Estructural <- est
  out$MedianAgePop$Ensamble    <- (out$MedianAgePop$ETS + est) / 2
  
  # La RS se proyecta además con la edad mediana estructural ya proyectada
  if ("RS" %in% names(M)) {
    est_rs <- proyectar_estructural_rs(M$RS, M$MedianAgePop, est, h, LIMITES$RS)
    out$RS$Estructural <- est_rs
    out$RS$Ensamble    <- (out$RS$ETS + est_rs) / 2
  }
  out
}

# 3. Backtesting con orígenes móviles ---------------------------------



backtest <- function(M_full, origen) {
  anios <- as.integer(colnames(M_full[[1]]))
  i0    <- which(anios == origen)
  n_tot <- length(anios)
  h     <- n_tot - i0
  M_tr  <- lapply(M_full, function(m) m[, 1:i0, drop = FALSE])
  pred  <- proyectar_todo(M_tr, h)
  
  bind_rows(lapply(names(M_full), function(v) {
    n   <- nrow(M_full[[v]])
    obs <- M_full[[v]][, (i0 + 1):n_tot, drop = FALSE]
    esc <- pmax(rowMeans(abs(t(diff(t(M_tr[[v]]))))), 1e-6)
    met <- pred[[v]]
    met$Naive <- matrix(rep(M_tr[[v]][, i0], times = h), nrow = n)
    bind_rows(lapply(names(met), function(m) data.frame(
      ISO3_code = rep(rownames(M_full[[v]]), times = h),
      Variable = v, Modelo = m, Origen = origen,
      h = rep(seq_len(h), each = n),
      pred = as.vector(met[[m]]), obs = as.vector(obs),
      escala = rep(esc, times = h)
    )))
  }))
}

cat("Backtesting con orígenes", paste(ORIGENES, collapse = ", "), "(puede tardar unos minutos)...\n")
bt <- bind_rows(lapply(ORIGENES, function(o) { cat("  origen", o, "\n"); backtest(M_hist, o) }))

val_pais <- bt %>%
  group_by(ISO3_code, Variable, Modelo, Origen) %>%
  summarise(MAE = mean(abs(obs - pred)), RMSE = sqrt(mean((obs - pred)^2)),
            MASE = MAE / first(escala), .groups = "drop")
write.csv(val_pais, out("validacion_por_pais.csv"), row.names = FALSE)


resumen_validacion <- bt %>%
  mutate(tramo = cut(h, c(0, 10, 20, Inf), labels = c("MASE_h1_10", "MASE_h11_20", "MASE_h21_mas")),
         ase = abs(obs - pred) / escala) %>%
  group_by(Variable, Modelo, tramo) %>%
  summarise(MASE = median(ase), .groups = "drop") %>%
  pivot_wider(names_from = tramo, values_from = MASE) %>%
  left_join(bt %>% group_by(Variable, Modelo) %>%
              summarise(MASE_global = median(abs(obs - pred) / escala), .groups = "drop"),
            by = c("Variable", "Modelo")) %>%
  arrange(Variable, MASE_global)


cat("\nValidación (mediana del error escalado; <1 = mejor que el naive de un paso):\n")
print(as.data.frame(resumen_validacion), digits = 3)
write.csv(resumen_validacion, out("resumen_validacion.csv"), row.names = FALSE)

# 4. Pronóstico final 2024-2100 ---------------------------------------

final <- proyectar_todo(M_modelo, H)
escala_final <- lapply(M_modelo, function(m) pmax(rowMeans(abs(t(diff(t(m))))), 1e-6))
metodo_para <- function(v) {
  m <- if (v %in% names(METODOS_POR_VARIABLE)) METODOS_POR_VARIABLE[[v]] else METODO_FINAL
  if (m %in% names(final[[v]])) m else "Ensamble"
}

# Intervalos empíricos: cuantiles del error escalado del backtesting por
# horizonte; más allá del horizonte validado (33 años) crecen con sqrt(h).
err_df <- bt %>%
  mutate(e = (obs - pred) / escala) %>%
  group_by(Variable, Modelo, ISO3_code, Origen) %>%
  mutate(err_serie = mean(abs(e))) %>%
  group_by(Variable, Modelo) %>%
  filter(err_serie <= quantile(err_serie, 1 - PROP_EXCLUIR_CHOQUES)) %>%
  ungroup()

bandas <- function(v, metodo) {
  q <- err_df %>%
    filter(Variable == v, Modelo == metodo) %>%
    group_by(h) %>%
    summarise(q025 = quantile(e, 0.025, na.rm = TRUE), q10 = quantile(e, 0.10, na.rm = TRUE),
              q90  = quantile(e, 0.90,  na.rm = TRUE), q975 = quantile(e, 0.975, na.rm = TRUE),
              .groups = "drop") %>%
    arrange(h)
  hmax <- nrow(q); hh <- seq_len(H)
  idx  <- pmin(hh, hmax); fac <- ifelse(hh > hmax, sqrt(hh / hmax), 1)
  list(q025 = cummin(pmin(q$q025[idx] * fac, 0)), q10 = cummin(pmin(q$q10[idx] * fac, 0)),
       q90  = cummax(pmax(q$q90[idx]  * fac, 0)), q975 = cummax(pmax(q$q975[idx] * fac, 0)))
}

proy_largo <- bind_rows(lapply(VARS, function(v) {
  met <- metodo_para(v); P <- final[[v]][[met]]; n <- nrow(P)
  b <- bandas(v, met); esc <- escala_final[[v]]; lim <- LIMITES[[v]]
  cl <- function(x) pmin(pmax(x, lim[1]), lim[2])
  data.frame(
    ISO3_code = rep(rownames(P), times = H), Time = rep(anios_fut, each = n),
    Variable = v, Metodo = met, Propia = as.vector(P),
    lo80 = cl(as.vector(P + esc %o% b$q10)),  hi80 = cl(as.vector(P + esc %o% b$q90)),
    lo95 = cl(as.vector(P + esc %o% b$q025)), hi95 = cl(as.vector(P + esc %o% b$q975))
  )
}))
saveRDS(final, out("proyecciones_todos_los_metodos.rds"))

# 5. Comparación contra la ONU ---------------------------------------

onu_long <- datos_onu %>%
  select(ISO3_code, Time, all_of(VARS)) %>%
  pivot_longer(all_of(VARS), names_to = "Variable", values_to = "ONU")

comparacion <- proy_largo %>%
  inner_join(onu_long, by = c("ISO3_code", "Time", "Variable")) %>%
  mutate(Discrepancia = Propia - ONU, ONU_en_IC95 = ONU >= lo95 & ONU <= hi95)

resumen_discrepancia <- comparacion %>%
  group_by(Variable) %>%
  summarise(disc_media = mean(Discrepancia, na.rm = TRUE),
            disc_abs_media = mean(abs(Discrepancia), na.rm = TRUE),
            pct_ONU_en_IC = 100 * mean(ONU_en_IC95, na.rm = TRUE), .groups = "drop")
cat("\nDiscrepancia del método final contra la ONU:\n"); print(as.data.frame(resumen_discrepancia), digits = 3)
write.csv(resumen_discrepancia, out("resumen_discrepancia.csv"), row.names = FALSE)

# Comparación de TODOS los métodos contra la ONU (solo como chequeo de
# razonabilidad: el método se elige por backtesting, no por parecerse a la ONU)
matriz_onu <- function(v) {
  m <- hacer_matriz(datos_onu, v)
  m[match(paises, rownames(m)), as.character(anios_fut), drop = FALSE]
}
cmp_metodos <- bind_rows(lapply(VARS, function(v) {
  O <- matriz_onu(v)
  bind_rows(lapply(names(final[[v]]), function(m) {
    P <- final[[v]][[m]]
    data.frame(Variable = v, Modelo = m,
               MAE_vs_ONU = mean(abs(P - O), na.rm = TRUE),
               MAE_vs_ONU_2100 = mean(abs(P[, H] - O[, H]), na.rm = TRUE),
               Sesgo_2100 = mean(P[, H] - O[, H], na.rm = TRUE))
  }))
})) %>% arrange(Variable, MAE_vs_ONU)
cat("\nDistancia a la ONU por método (menor = más parecido):\n"); print(as.data.frame(cmp_metodos), digits = 3)
write.csv(cmp_metodos, out("comparacion_metodos_vs_ONU.csv"), row.names = FALSE)

# Diagnóstico de topes (idealmente cercano a 0 %)
diag_topes <- comparacion %>%
  mutate(lim_inf = vapply(Variable, function(v) LIMITES[[v]][1], numeric(1)),
         lim_sup = vapply(Variable, function(v) LIMITES[[v]][2], numeric(1))) %>%
  group_by(Variable) %>%
  summarise(pct_en_tope = 100 * mean(Propia <= lim_inf | Propia >= lim_sup, na.rm = TRUE), .groups = "drop")
cat("\nDiagnóstico de topes (idealmente cercano a 0 %):\n"); print(as.data.frame(diag_topes))

# Velocidad de envejecimiento (años de edad mediana por década)
velocidad <- comparacion %>%
  filter(Variable == "MedianAgePop") %>%
  arrange(ISO3_code, Time) %>%
  group_by(ISO3_code) %>%
  mutate(Vel_Propia = (Propia - lag(Propia)) * 10, Vel_ONU = (ONU - lag(ONU)) * 10) %>%
  ungroup() %>% select(ISO3_code, Time, Vel_Propia, Vel_ONU)

# 6. Gráficos ----------------------------------------------------------

if (PAIS_FOCO %in% paises) {
  hist_foco <- datos_hist %>% filter(ISO3_code == PAIS_FOCO) %>%
    select(Time, all_of(VARS)) %>% pivot_longer(-Time, names_to = "Variable", values_to = "Valor")
  fut_foco <- comparacion %>% filter(ISO3_code == PAIS_FOCO)
  
  g_foco <- ggplot() +
    geom_line(data = hist_foco, aes(Time, Valor), colour = "grey30") +
    geom_ribbon(data = fut_foco, aes(Time, ymin = lo95, ymax = hi95), fill = "steelblue", alpha = 0.2) +
    geom_line(data = fut_foco, aes(Time, Propia, colour = "Propia")) +
    geom_line(data = fut_foco, aes(Time, ONU, colour = "ONU Medium"), linetype = "dashed") +
    facet_wrap(~ Variable, scales = "free_y") +
    scale_colour_manual(values = c("Propia" = "steelblue", "ONU Medium" = "firebrick")) +
    labs(title = paste("Proyecciones propias vs. ONU:", PAIS_FOCO),
         subtitle = "Método elegido por variable (METODOS_POR_VARIABLE) · banda = IC95 empírico del backtesting",
         x = NULL, y = NULL, colour = NULL) +
    theme_minimal() + theme(legend.position = "bottom")
  ggsave(out("grafico_colombia.png"), g_foco, width = 12, height = 8, dpi = 150)
  
  # Todos los métodos para la edad mediana, para elegir con criterio
  met_col <- bind_rows(lapply(names(final$MedianAgePop), function(m) data.frame(
    Time = anios_fut, Valor = final$MedianAgePop[[m]][PAIS_FOCO, ], Modelo = m)))
  g_met <- ggplot() +
    geom_line(data = hist_foco %>% filter(Variable == "MedianAgePop"), aes(Time, Valor), colour = "grey30") +
    geom_line(data = met_col, aes(Time, Valor, colour = Modelo), linewidth = 1) +
    geom_line(data = fut_foco %>% filter(Variable == "MedianAgePop"), aes(Time, ONU),
              colour = "black", linetype = "dashed") +
    labs(title = paste("Edad mediana", PAIS_FOCO, ": métodos vs. ONU (negro discontinuo)"),
         x = NULL, y = "Años", colour = NULL) +
    theme_minimal() + theme(legend.position = "bottom")
  ggsave(out("grafico_metodos_edad_mediana.png"), g_met, width = 10, height = 6, dpi = 150)
}

g_val <- val_pais %>%
  filter(is.finite(MASE), MASE > 0) %>%
  ggplot(aes(Modelo, MASE)) +
  geom_boxplot(outlier.alpha = 0.3) +
  geom_hline(yintercept = 1, linetype = "dashed", colour = "firebrick") +
  scale_y_log10() +
  facet_wrap(~ Variable, scales = "free_y") +
  labs(title = "Backtesting con orígenes móviles (1990, 2000, 2010)",
       subtitle = "MASE < 1: mejor que el naive de un paso", x = NULL, y = "MASE (escala log)") +
  theme_minimal() + theme(axis.text.x = element_text(angle = 30, hjust = 1))
ggsave(out("grafico_validacion.png"), g_val, width = 12, height = 8, dpi = 150)

# 6b. Punto crítico pensional ------------------------------------------
# Año crítico = primer año desde el cual la RS SE MANTIENE por debajo del umbral.
anio_critico <- function(t, rs, umbral) {
  ok <- rs < umbral
  if (all(is.na(ok))) return(NA_real_)
  if (all(ok))        return(min(t))          # ya está por debajo
  if (tail(ok, 1))    return(max(t[!ok]) + 1) # se mantiene por debajo desde ese año
  NA_real_                                    # no se estabiliza por debajo antes de 2100
}

if ("RS" %in% VARS) {
  criticos <- comparacion %>%
    filter(Variable == "RS") %>%
    arrange(ISO3_code, Time) %>%
    group_by(ISO3_code) %>%
    summarise(
      Critico_Propia      = anio_critico(Time, Propia, UMBRAL_RS),
      Critico_ONU         = anio_critico(Time, ONU,    UMBRAL_RS),
      Critico_IC_temprano = anio_critico(Time, lo95,   UMBRAL_RS),   # RS baja -> antes
      Critico_IC_tardio   = anio_critico(Time, hi95,   UMBRAL_RS),
      .groups = "drop"
    ) %>%
    mutate(Diferencia_anios = Critico_Propia - Critico_ONU)
  write.csv(criticos, out("puntos_criticos_RS.csv"), row.names = FALSE)
  
  cat("\nPunto crítico (RS <", UMBRAL_RS, ") en", PAIS_FOCO, ":\n")
  print(as.data.frame(criticos %>% filter(ISO3_code == PAIS_FOCO)))
  cat("Países que nunca cruzan el umbral de forma sostenida (propio):",
      sum(is.na(criticos$Critico_Propia)), "de", nrow(criticos), "\n")
  
  if (PAIS_FOCO %in% paises) {
    rs_hist <- datos_hist %>% filter(ISO3_code == PAIS_FOCO) %>% select(Time, RS)
    rs_fut  <- comparacion %>% filter(ISO3_code == PAIS_FOCO, Variable == "RS")
    g_rs <- ggplot() +
      geom_line(data = rs_hist, aes(Time, RS), colour = "grey30") +
      geom_ribbon(data = rs_fut, aes(Time, ymin = lo95, ymax = hi95), fill = "steelblue", alpha = 0.2) +
      geom_line(data = rs_fut, aes(Time, Propia, colour = "Propia")) +
      geom_line(data = rs_fut, aes(Time, ONU, colour = "ONU Medium"), linetype = "dashed") +
      geom_hline(yintercept = UMBRAL_RS, linetype = "dotted") +
      scale_colour_manual(values = c("Propia" = "steelblue", "ONU Medium" = "firebrick")) +
      labs(title = paste("Relación de soporte (15-64 / 65+):", PAIS_FOCO),
           subtitle = paste("Umbral =", UMBRAL_RS, "trabajadores por pensionado"),
           x = NULL, y = "RS", colour = NULL) +
      theme_minimal() + theme(legend.position = "bottom")
    ggsave(out("grafico_relacion_soporte.png"), g_rs, width = 9, height = 5, dpi = 150)
  }
} else {
  message("Sin RS en los datos: no se calculan puntos críticos.")
}

# 7. Exportación (formato que lee la app Shiny) -----------------------

salida_ancha <- comparacion %>%
  select(ISO3_code, Time, Variable, Propia, ONU, Discrepancia, lo95, hi95) %>%
  pivot_wider(names_from = Variable, values_from = c(Propia, ONU, Discrepancia, lo95, hi95),
              names_glue = "{Variable}_{.value}") %>%
  left_join(velocidad, by = c("ISO3_code", "Time"))

historico_largo <- datos_hist %>%
  filter(ISO3_code %in% paises) %>%
  select(any_of(c("ISO3_code", "Location")), Time, all_of(VARS)) %>%
  pivot_longer(all_of(VARS), names_to = "Variable", values_to = "Valor")

write.csv(comparacion,     out("Proyecciones_Propias_vs_ONU_largo.csv"), row.names = FALSE)
write.csv(salida_ancha,    out("Proyecciones_Propias_vs_ONU.csv"),       row.names = FALSE)
write.csv(historico_largo, out("historico_largo.csv"), row.names = FALSE, fileEncoding = "UTF-8")
cat("\nArchivos guardados en:", normalizePath(dir_out), "\n")

# 8. Cierre ------------------------------------------------------------
writeLines(capture.output(sessionInfo()), out("sessionInfo.txt"))
dbDisconnect(con, shutdown = TRUE)







x <- read.csv("outputs/puntos_criticos_RS.csv")
table(propia = !is.na(x$Critico_Propia), onu = !is.na(x$Critico_ONU))
d <- x$Critico_Propia - x$Critico_ONU
c(mediana = median(d, na.rm = TRUE), dentro_5_anios = mean(abs(d) <= 5, na.rm = TRUE))
