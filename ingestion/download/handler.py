"""Paso 1 de la ingesta: descarga el catálogo de MedlinePlus y lo deja en S3.
Corre fuera de la VPC, por lo que tiene salida a internet sin NAT.
Solo sube el archivo si cambió respecto a la última corrida.
"""

import hashlib
import os
import urllib.request

import boto3

s3 = boto3.client("s3")

SOURCE_URL = os.environ["SOURCE_URL"]
BUCKET = os.environ["BUCKET"]
EXPECTED_BUCKET_OWNER = os.environ["EXPECTED_BUCKET_OWNER"]
HASH_KEY = "_meta/last_hash.txt"
CATALOG_KEY = os.environ.get("CATALOG_KEY", "incoming/catalog.zip")


def _last_hash() -> str | None:
    try:
        obj = s3.get_object(
            Bucket=BUCKET,
            Key=HASH_KEY,
            ExpectedBucketOwner=EXPECTED_BUCKET_OWNER,
        )
        return obj["Body"].read().decode().strip()
    except s3.exceptions.NoSuchKey:
        return None


def main(event, context):
    with urllib.request.urlopen(SOURCE_URL, timeout=90) as resp:
        data = resp.read()

    digest = hashlib.sha256(data).hexdigest()

    if digest == _last_hash():
        return {"status": "unchanged"}

    s3.put_object(
        Bucket=BUCKET,
        Key=CATALOG_KEY,
        Body=data,
        ExpectedBucketOwner=EXPECTED_BUCKET_OWNER,
    )

    s3.put_object(
        Bucket=BUCKET,
        Key=HASH_KEY,
        Body=digest.encode(),
        ExpectedBucketOwner=EXPECTED_BUCKET_OWNER,
    )

    return {"status": "uploaded", "bytes": len(data)}
