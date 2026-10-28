# ==============================================================================
# ASA DataQuest 2026 - WPP2024
# Script 04: Geometrías de países (Natural Earth), cruce por ISO3 y puntos representativos
# ------------------------------------------------------------------------------
# Objetivo: dejar listas las fronteras para la fase espacial y DOCUMENTAR qué países
# de WPP no tienen polígono (principio B1 de la ASA: procesamiento y faltantes).
#
# Entradas : data/clean/wpp_paises_medium_suppl.parquet (script 00)
#            Paquete rnaturalearthdata (fronteras 1:50m; no requiere internet)
# Salidas  : data/clean/mundo_geom.rds     (sf polígonos: iso3, nombre_ne)
#            data/clean/mundo_puntos.rds   (sf puntos: un punto dentro del polígono
#                                           MÁS GRANDE de cada país; base de los vecinos kNN)
#            data/raw/externos/natural_earth_admin0_50m.gpkg (copia para reproducibilidad)
#            output/tablas/04_*.csv
# Ejecutar de arriba hacia abajo, desde la raíz del proyecto.
# ==============================================================================

# ---- 0. Entorno --------------------------------------------------------------
if (!file.exists("R/config.R")) stop("Abre el proyecto (.Rproj) o fija setwd() en la raíz.")
paquetes <- c("DBI", "duckdb", "dplyr", "tidyr", "glue", "tibble",
              "sf", "rnaturalearth", "rnaturalearthdata")
faltan <- setdiff(paquetes, rownames(installed.packages()))
if (length(faltan) > 0) install.packages(faltan)
invisible(lapply(paquetes, library, character.only = TRUE))
source("R/config.R",      encoding = "UTF-8")
source("R/utils_datos.R", encoding = "UTF-8")
crear_directorios()
suppressMessages(sf::sf_use_s2(TRUE))   # geometría esférica: áreas y distancias correctas en lon/lat

ESCALA_NE <- 50    # 110 (muy simple), 50 (recomendada) o 10 (requiere rnaturalearthhires)

# Correcciones manuales de código NE -> código WPP (D22). Se llenan DESPUÉS de leer las
# listas de la sección 4; cada entrada debe quedar justificada en DECISIONES.md.
# Ejemplo: RECODIFICAR_NE <- c("KOS" = "XXX")
RECODIFICAR_NE <- setNames(character(0), character(0))

con <- conectar_duckdb(if (exists("con")) con else NULL)
dbExecute(con, glue("CREATE OR REPLACE VIEW wpp AS
                     SELECT * FROM read_parquet('{file.path(CFG$dir_clean, CFG$f_parquet)}')"))


# ---- 1. Países de WPP y universo de análisis (D12) ---------------------------
seccion("1. PAÍSES DE WPP")

wpp_paises <- dbGetQuery(con, glue("
  SELECT LocID, ISO3_code AS iso3, Location, TPopulation1July AS pob_2023_miles
  FROM wpp WHERE Time = {CFG$ultimo_anio_estimado}")) |>
  mutate(en_universo = pob_2023_miles >= CFG$umbral_universo_miles)

verificar(nrow(wpp_paises) == 237, "237 países/áreas en WPP.",
          paste("Se esperaban 237 y hay", nrow(wpp_paises)))
cat("Universo (>= ", CFG$umbral_universo_miles, " miles de habitantes): ",
    sum(wpp_paises$en_universo), " países.\n", sep = "")


# ---- 2. Fronteras Natural Earth ----------------------------------------------
seccion("2. FRONTERAS NATURAL EARTH")

mundo_raw <- rnaturalearth::ne_countries(scale = ESCALA_NE, returnclass = "sf")
cat("Filas:", nrow(mundo_raw), "| CRS:", sf::st_crs(mundo_raw)$input, "\n")

# Código ISO3: iso_a3 trae "-99" en varios países (p. ej. Francia, Noruega). Se completa
# con iso_a3_eh y adm0_a3, en ese orden.
cols_codigo <- intersect(c("iso_a3", "iso_a3_eh", "adm0_a3"), names(mundo_raw))
verificar(length(cols_codigo) > 0, paste("Columnas de código:", paste(cols_codigo, collapse = ", ")),
          "Natural Earth no trae ninguna columna de código ISO3 conocida.")
codigo <- rep(NA_character_, nrow(mundo_raw))
for (cc in cols_codigo) {
  v <- as.character(mundo_raw[[cc]])
  v[v %in% c("-99", "-099", "")] <- NA
  codigo <- dplyr::coalesce(codigo, v)
}
col_nombre <- intersect(c("name_long", "name", "admin"), names(mundo_raw))[1]

mundo <- mundo_raw
mundo$iso3 <- codigo
mundo$nombre_ne <- as.character(mundo_raw[[col_nombre]])
mundo <- mundo[, c("iso3", "nombre_ne")]

# Recodificaciones manuales (vacías por defecto)
idx <- match(mundo$iso3, names(RECODIFICAR_NE))
mundo$iso3[!is.na(idx)] <- unname(RECODIFICAR_NE[idx[!is.na(idx)]])

sin_codigo <- mundo |> sf::st_drop_geometry() |> filter(is.na(iso3))
if (nrow(sin_codigo) > 0) {
  cat("Polígonos sin código ISO3 (se descartan):", paste(sin_codigo$nombre_ne, collapse = " | "), "\n")
}
mundo <- mundo |> filter(!is.na(iso3), iso3 != "ATA")     # sin Antártida

mundo <- sf::st_transform(mundo, 4326) |> sf::st_make_valid()
if (any(as.character(sf::st_geometry_type(mundo)) == "GEOMETRYCOLLECTION")) {
  mundo <- sf::st_collection_extract(mundo, "POLYGON")
}

dup <- mundo |> sf::st_drop_geometry() |> count(iso3) |> filter(n > 1)
if (nrow(dup) > 0) {
  cat("Códigos repetidos (se disuelven en un solo país):", paste(dup$iso3, collapse = ", "), "\n")
  mundo <- mundo |> group_by(iso3) |>
    summarise(nombre_ne = first(nombre_ne), .groups = "drop")
}
verificar(!anyDuplicated(mundo$iso3), paste0(nrow(mundo), " polígonos con ISO3 único."),
          "Persisten ISO3 duplicados tras disolver.")


# ---- 3. Cruce con WPP --------------------------------------------------------
seccion("3. CRUCE POR ISO3")

cruce <- wpp_paises |> mutate(tiene_poligono = iso3 %in% mundo$iso3)
wpp_sin_pol <- cruce |> filter(!tiene_poligono) |> arrange(desc(pob_2023_miles))
ne_sin_wpp <- mundo |> sf::st_drop_geometry() |> filter(!iso3 %in% wpp_paises$iso3)

cat(sprintf("WPP con polígono: %d de %d | del universo: %d de %d\n",
            sum(cruce$tiene_poligono), nrow(cruce),
            sum(cruce$tiene_poligono & cruce$en_universo), sum(cruce$en_universo)))
cat("\nPaíses/áreas de WPP SIN polígono (mayor población primero):\n")
ver(wpp_sin_pol |> select(iso3, Location, pob_2023_miles, en_universo) |> head(30))
cat("\nPolígonos de Natural Earth SIN contraparte en WPP:\n")
ver(ne_sin_wpp)

verificar(all(cruce$tiene_poligono[cruce$en_universo]),
          "Todos los países del universo tienen polígono.",
          paste("Universo sin polígono:",
                paste(cruce$iso3[cruce$en_universo & !cruce$tiene_poligono], collapse = ", "),
                "-> revisar con RECODIFICAR_NE (D22) o escala 10m."), fatal = FALSE)


# ---- 4. Puntos representativos (polígono más grande de cada país) ------------
seccion("4. PUNTOS REPRESENTATIVOS")

# Francia incluye la Guayana Francesa, Noruega incluye Svalbard, etc. Usar el centroide
# del multipolígono completo movería el punto hacia el océano. Se toma un punto DENTRO
# del polígono individual de mayor área.
partes <- suppressWarnings(sf::st_cast(mundo, "POLYGON"))
partes$area <- as.numeric(sf::st_area(partes))
principal <- partes |> group_by(iso3) |> slice_max(area, n = 1, with_ties = FALSE) |> ungroup()
pts <- suppressWarnings(sf::st_point_on_surface(principal))
pts <- pts[, c("iso3", "nombre_ne")]
co <- sf::st_coordinates(pts)
pts$lon <- co[, 1]
pts$lat <- co[, 2]
verificar(nrow(pts) == nrow(mundo), "Un punto representativo por país.",
          "El número de puntos no coincide con el de polígonos.")
cat("Ejemplos (Francia, Colombia, Indonesia):\n")
ver(pts |> sf::st_drop_geometry() |> filter(iso3 %in% c("FRA", "COL", "IDN")))


# ---- 5. Guardado y registro --------------------------------------------------
seccion("5. GUARDADO")

saveRDS(mundo, file.path(CFG$dir_clean, "mundo_geom.rds"))
saveRDS(pts,   file.path(CFG$dir_clean, "mundo_puntos.rds"))
write.csv(cruce,       file.path(CFG$dir_tablas, "04_cruce_iso3_wpp_ne.csv"), row.names = FALSE)
write.csv(wpp_sin_pol, file.path(CFG$dir_tablas, "04_wpp_sin_poligono.csv"),  row.names = FALSE)
write.csv(ne_sin_wpp,  file.path(CFG$dir_tablas, "04_ne_sin_wpp.csv"),        row.names = FALSE)

f_gpkg <- file.path(CFG$dir_externos, "natural_earth_admin0_50m.gpkg")
if (ESCALA_NE == 50 && !file.exists(f_gpkg)) {
  dir.create(CFG$dir_externos, showWarnings = FALSE, recursive = TRUE)
  tryCatch(sf::st_write(mundo_raw, f_gpkg, quiet = TRUE),
           error = function(e) cat("  (No se pudo guardar la copia .gpkg:", conditionMessage(e), ")\n"))
}

cat("\nRegistrar en data/raw/externos/FUENTES.md (entrada E5):\n",
    "  Fuente   : Natural Earth, Admin 0 - Countries, escala 1:", ESCALA_NE, "\n",
    "  Acceso   : paquete rnaturalearth ", as.character(packageVersion("rnaturalearth")),
    " / rnaturalearthdata ", as.character(packageVersion("rnaturalearthdata")),
    " | fecha: ", format(Sys.Date()), "\n",
    "  Licencia : Natural Earth se declara de dominio público; confirmar en\n",
    "             naturalearthdata.com/about/terms-of-use antes de citarlo.\n",
    "  Transf.  : sin Antártida; ISO3 = iso_a3, completado con iso_a3_eh y adm0_a3;\n",
    "             geometrías validadas; recodificaciones: ",
    if (length(RECODIFICAR_NE) == 0) "ninguna" else paste(names(RECODIFICAR_NE), "->", RECODIFICAR_NE, collapse = ", "),
    "\n", sep = "")
cat("Mapas: las fronteras son ilustrativas y no implican reconocimiento oficial alguno.\n")

# dbDisconnect(con, shutdown = TRUE)
