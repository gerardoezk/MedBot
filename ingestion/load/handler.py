"""Paso 2 de la ingesta: lee el catálogo de MedlinePlus desde S3 y lo carga en RDS.

Esta Lambda corre dentro de la VPC. Puede leer S3 mediante Gateway Endpoint y
conectarse a RDS PostgreSQL. El archivo de MedlinePlus puede venir como XML directo
o como ZIP comprimido; ambos formatos son soportados.

La carga es atómica: primero se inserta todo en catalog_staging y, si la validación
pasa, se reemplaza catalog dentro de una transacción.
"""

import io
import json
import os
import re
import zipfile
import xml.etree.ElementTree as ET

import boto3
import psycopg2

s3 = boto3.client("s3")
secrets = boto3.client("secretsmanager")

BUCKET = os.environ["BUCKET"]
DB_SECRET_ARN = os.environ["DB_SECRET_ARN"]
CATALOG_KEY = os.environ.get("CATALOG_KEY", "incoming/catalog.zip")

# Si el catálogo trae menos temas que esto, asumimos descarga corrupta o archivo incorrecto.
MIN_EXPECTED_TOPICS = 1000


SCHEMA_SQL = """
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE IF NOT EXISTS catalog (
    id      SERIAL PRIMARY KEY,
    title   TEXT NOT NULL,
    url     TEXT,
    summary TEXT
);

CREATE TABLE IF NOT EXISTS catalog_staging (
    id      SERIAL PRIMARY KEY,
    title   TEXT NOT NULL,
    url     TEXT,
    summary TEXT
);

CREATE INDEX IF NOT EXISTS idx_catalog_title_trgm
    ON catalog USING gin (title gin_trgm_ops);
"""


def _db_conn():
    creds = json.loads(secrets.get_secret_value(SecretId=DB_SECRET_ARN)["SecretString"])
    return psycopg2.connect(
        host=creds["host"],
        port=creds.get("port", 5432),
        dbname=creds["dbname"],
        user=creds["username"],
        password=creds["password"],
    )


def _extract_xml(payload: bytes) -> bytes:
    """Devuelve XML aunque el archivo original venga comprimido como ZIP."""
    is_zip = payload.startswith(b"PK\x03\x04")

    if not is_zip:
        return payload

    with zipfile.ZipFile(io.BytesIO(payload)) as zf:
        xml_files = [
            name for name in zf.namelist()
            if name.lower().endswith(".xml") and not name.endswith("/")
        ]

        if not xml_files:
            raise ValueError("El ZIP de MedlinePlus no contiene archivos XML.")

        # En caso haya más de un XML, usamos el de mayor tamaño porque suele ser el catálogo principal.
        xml_name = max(xml_files, key=lambda name: zf.getinfo(name).file_size)
        return zf.read(xml_name)


def _clean_text(value: str) -> str:
    return re.sub(r"\s+", " ", value or "").strip()


def _element_text(element) -> str:
    if element is None:
        return ""
    return _clean_text(" ".join(element.itertext()))


def _parse_topics(payload: bytes) -> list[tuple[str, str, str]]:
    xml_bytes = _extract_xml(payload)
    root = ET.fromstring(xml_bytes)

    topics = []

    for topic in root.iter("health-topic"):
        title = _clean_text(topic.get("title", ""))
        url = _clean_text(topic.get("url", ""))
        summary = _element_text(topic.find("full-summary"))

        if title:
            topics.append((title, url, summary))

    return topics


def _ensure_schema(cursor):
    for statement in SCHEMA_SQL.split(";"):
        statement = statement.strip()
        if statement:
            cursor.execute(statement + ";")


def main(event, context):
    obj = s3.get_object(Bucket=BUCKET, Key=CATALOG_KEY)
    payload = obj["Body"].read()

    topics = _parse_topics(payload)

    if len(topics) < MIN_EXPECTED_TOPICS:
        raise ValueError(f"Catálogo sospechoso: solo se encontraron {len(topics)} temas.")

    conn = _db_conn()

    try:
        with conn, conn.cursor() as cur:
            _ensure_schema(cur)

            cur.execute("TRUNCATE catalog_staging RESTART IDENTITY;")

            cur.executemany(
                """
                INSERT INTO catalog_staging (title, url, summary)
                VALUES (%s, %s, %s);
                """,
                topics,
            )

            cur.execute("TRUNCATE catalog RESTART IDENTITY;")
            cur.execute(
                """
                INSERT INTO catalog (title, url, summary)
                SELECT title, url, summary
                FROM catalog_staging;
                """
            )

        return {
            "status": "loaded",
            "topics": len(topics),
            "source": CATALOG_KEY,
        }

    finally:
        conn.close()