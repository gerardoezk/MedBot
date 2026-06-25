-- Esquema del catálogo de MedlinePlus.
-- pg_trgm habilita la búsqueda tolerante a errores de tipeo ("diabetis" -> "diabetes").

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE IF NOT EXISTS catalog (
    id      SERIAL PRIMARY KEY,
    title   TEXT NOT NULL,
    url     TEXT,
    summary TEXT
);

-- Tabla espejo para la carga atómica (staging -> swap).
CREATE TABLE IF NOT EXISTS catalog_staging (LIKE catalog INCLUDING ALL);

-- Índice trigram sobre el título para la búsqueda por similitud.
CREATE INDEX IF NOT EXISTS idx_catalog_title_trgm
    ON catalog USING gin (title gin_trgm_ops);

-- Ejemplo de consulta del buscador (ordena por similitud):
--   SELECT title, url, summary
--   FROM catalog
--   WHERE title % :q
--   ORDER BY similarity(title, :q) DESC
--   LIMIT 5;
