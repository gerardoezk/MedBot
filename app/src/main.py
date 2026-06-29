"""API del buscador MedBot.

Expone:
- /health: usado por el ALB para verificar que la app esté viva.
- /search: busca temas de salud en el catálogo local cargado desde MedlinePlus.

La app no consulta internet para responder al usuario. Solo usa la base PostgreSQL
alimentada previamente por la ingesta de MedlinePlus.
"""

import os

import psycopg2
from fastapi import FastAPI, HTTPException, Query

app = FastAPI(title="MedBot")


DISCLAIMER = (
    "Información basada en MedlinePlus. No sustituye la evaluación, diagnóstico "
    "ni tratamiento de un profesional de salud."
)


def _conn():
    return psycopg2.connect(
        host=os.environ["host"],
        port=os.environ.get("port", 5432),
        dbname=os.environ["dbname"],
        user=os.environ["username"],
        password=os.environ["password"],
        connect_timeout=5,
    )


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/search")
def search(q: str = Query(..., min_length=2, max_length=120)):
    query = " ".join(q.strip().split())

    if len(query) < 2:
        raise HTTPException(status_code=400, detail="La consulta debe tener al menos 2 caracteres.")

    try:
        conn = _conn()
        try:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT title, url, summary, similarity(title, %s) AS score
                    FROM catalog
                    WHERE
                        title ILIKE %s
                        OR title %% %s
                        OR summary ILIKE %s
                    ORDER BY
                        CASE
                            WHEN lower(title) = lower(%s) THEN 1
                            WHEN title ILIKE %s THEN 2
                            ELSE 3
                        END,
                        score DESC,
                        title ASC
                    LIMIT 5;
                    """,
                    (
                        query,
                        f"%{query}%",
                        query,
                        f"%{query}%",
                        query,
                        f"%{query}%",
                    ),
                )
                rows = cur.fetchall()
        finally:
            conn.close()

    except psycopg2.Error as exc:
        raise HTTPException(
            status_code=503,
            detail="No se pudo consultar temporalmente la base de datos médica.",
        ) from exc

    results = [
        {
            "title": row[0],
            "url": row[1],
            "summary": row[2],
            "score": round(float(row[3] or 0), 3),
            "source": "MedlinePlus",
        }
        for row in rows
    ]

    return {
        "query": query,
        "count": len(results),
        "results": results,
        "message": (
            "Se encontraron temas relacionados en el catálogo de MedlinePlus."
            if results
            else "No se encontraron coincidencias claras. Intenta escribir otro término médico."
        ),
        "disclaimer": DISCLAIMER,
    }