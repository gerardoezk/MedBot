"""API del buscador MedBot. Expone /health (para el ALB) y /search."""
import os

import psycopg2
from fastapi import FastAPI, Query

app = FastAPI(title="MedBot")


def _conn():
    return psycopg2.connect(
        host=os.environ["host"],
        dbname=os.environ["dbname"],
        user=os.environ["username"],
        password=os.environ["password"],
    )


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/search")
def search(q: str = Query(..., min_length=2)):
    conn = _conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT title, url, summary
                FROM catalog
                WHERE title %% %s
                ORDER BY similarity(title, %s) DESC
                LIMIT 5;
                """,
                (q, q),
            )
            rows = cur.fetchall()
        return {
            "query": q,
            "results": [
                {"title": r[0], "url": r[1], "summary": r[2]} for r in rows
            ],
            "disclaimer": "Información de MedlinePlus. No sustituye consejo médico profesional.",
        }
    finally:
        conn.close()
