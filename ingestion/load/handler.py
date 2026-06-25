"""Paso 2 de la ingesta: lee el XML de S3, lo valida y lo carga en RDS de forma atómica.
Corre DENTRO de la VPC; llega a S3 por el Gateway Endpoint (sin NAT).

Carga atómica: se inserta todo en una tabla `catalog_staging` y, solo si la validación
pasa, se hace el swap a `catalog` dentro de una transacción. Así el usuario nunca ve
el catálogo a medio actualizar (RNF de "sin downtime").
"""
import json
import os
import xml.etree.ElementTree as ET

import boto3
import psycopg2  # incluir psycopg2-binary en el paquete de la Lambda

s3 = boto3.client("s3")
secrets = boto3.client("secretsmanager")
BUCKET = os.environ["BUCKET"]
DB_SECRET_ARN = os.environ["DB_SECRET_ARN"]

# Si el catálogo trae menos temas que esto, asumimos descarga corrupta y abortamos.
MIN_EXPECTED_TOPICS = 1000


def _db_conn():
    creds = json.loads(secrets.get_secret_value(SecretId=DB_SECRET_ARN)["SecretString"])
    return psycopg2.connect(
        host=creds["host"],
        port=creds.get("port", 5432),
        dbname=creds["dbname"],
        user=creds["username"],
        password=creds["password"],
    )


def _parse_topics(xml_bytes: bytes) -> list[tuple]:
    root = ET.fromstring(xml_bytes)
    topics = []
    for t in root.iter("health-topic"):
        title = t.get("title", "").strip()
        url = t.get("url", "").strip()
        summary_el = t.find("full-summary")
        summary = (summary_el.text or "").strip() if summary_el is not None else ""
        if title:
            topics.append((title, url, summary))
    return topics


def main(event, context):
    obj = s3.get_object(Bucket=BUCKET, Key="incoming/catalog.xml")
    topics = _parse_topics(obj["Body"].read())

    # Guarda de validación: si viene casi vacío, fallamos a propósito.
    # El error hace que el evento caiga en la DLQ y dispare la alerta.
    if len(topics) < MIN_EXPECTED_TOPICS:
        raise ValueError(f"Catálogo sospechoso: solo {len(topics)} temas")

    conn = _db_conn()
    try:
        with conn, conn.cursor() as cur:
            cur.execute("TRUNCATE catalog_staging;")
            cur.executemany(
                "INSERT INTO catalog_staging (title, url, summary) VALUES (%s, %s, %s);",
                topics,
            )
            # Swap atómico: dentro de la misma transacción.
            cur.execute("TRUNCATE catalog;")
            cur.execute("INSERT INTO catalog SELECT * FROM catalog_staging;")
        return {"status": "loaded", "topics": len(topics)}
    finally:
        conn.close()
