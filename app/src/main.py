"""API del buscador MedBot.

Expone:
- /: interfaz visual tipo chat para consultar temas médicos.
- /health: usado por el ALB para verificar que la app esté viva.
- /search: busca temas de salud en el catálogo local cargado desde MedlinePlus.

La app no consulta internet para responder al usuario. Solo usa la base PostgreSQL
alimentada previamente por la ingesta de MedlinePlus.
"""

import os

import psycopg2
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import HTMLResponse

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


@app.get("/", response_class=HTMLResponse)
def home():
    return """
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>MedBot | Asistente Médico Virtual</title>
  <style>
    :root {
      --bg: #eef4ff;
      --card: #ffffff;
      --primary: #1d4ed8;
      --primary-dark: #1e40af;
      --text: #172033;
      --muted: #667085;
      --border: #d9e2f2;
      --bot: #f4f7fb;
      --user: #dbeafe;
      --danger: #b42318;
    }

    * {
      box-sizing: border-box;
    }

    body {
      margin: 0;
      font-family: Arial, Helvetica, sans-serif;
      background: linear-gradient(135deg, #e0f2fe 0%, #eef4ff 45%, #ffffff 100%);
      color: var(--text);
    }

    .page {
      min-height: 100vh;
      display: flex;
      justify-content: center;
      align-items: center;
      padding: 24px;
    }

    .app {
      width: 100%;
      max-width: 980px;
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 24px;
      box-shadow: 0 20px 50px rgba(15, 23, 42, 0.12);
      overflow: hidden;
    }

    .header {
      padding: 28px 32px;
      background: linear-gradient(135deg, #1d4ed8 0%, #2563eb 50%, #38bdf8 100%);
      color: white;
    }

    .header h1 {
      margin: 0;
      font-size: 32px;
      letter-spacing: -0.5px;
    }

    .header p {
      margin: 8px 0 0;
      font-size: 15px;
      opacity: 0.95;
    }

    .content {
      padding: 24px;
    }

    .notice {
      background: #fff7ed;
      border: 1px solid #fed7aa;
      color: #7c2d12;
      padding: 12px 14px;
      border-radius: 14px;
      font-size: 14px;
      margin-bottom: 18px;
    }

    .chat {
      height: 440px;
      overflow-y: auto;
      border: 1px solid var(--border);
      border-radius: 18px;
      background: #fbfdff;
      padding: 18px;
    }

    .msg {
      display: flex;
      margin-bottom: 14px;
    }

    .msg.user {
      justify-content: flex-end;
    }

    .bubble {
      max-width: 82%;
      padding: 13px 15px;
      border-radius: 16px;
      line-height: 1.45;
      font-size: 15px;
    }

    .bot .bubble {
      background: var(--bot);
      border: 1px solid var(--border);
    }

    .user .bubble {
      background: var(--user);
      border: 1px solid #bfdbfe;
    }

    .result-card {
      background: white;
      border: 1px solid var(--border);
      border-radius: 14px;
      padding: 14px;
      margin-top: 10px;
    }

    .result-card h3 {
      margin: 0 0 8px;
      color: var(--primary-dark);
      font-size: 18px;
    }

    .result-card .summary {
      color: #344054;
      font-size: 14px;
      max-height: 170px;
      overflow: auto;
    }

    .result-card a {
      display: inline-block;
      margin-top: 10px;
      color: var(--primary);
      font-weight: bold;
      text-decoration: none;
    }

    .result-card a:hover {
      text-decoration: underline;
    }

    .search-box {
      display: flex;
      gap: 10px;
      margin-top: 18px;
    }

    input {
      flex: 1;
      padding: 14px 16px;
      border: 1px solid var(--border);
      border-radius: 14px;
      font-size: 16px;
      outline: none;
    }

    input:focus {
      border-color: #60a5fa;
      box-shadow: 0 0 0 4px rgba(96, 165, 250, 0.18);
    }

    button {
      border: none;
      border-radius: 14px;
      padding: 0 22px;
      background: var(--primary);
      color: white;
      font-size: 16px;
      font-weight: bold;
      cursor: pointer;
    }

    button:hover {
      background: var(--primary-dark);
    }

    button:disabled {
      opacity: 0.6;
      cursor: not-allowed;
    }

    .examples {
      margin-top: 14px;
      color: var(--muted);
      font-size: 14px;
    }

    .examples button {
      margin: 6px 6px 0 0;
      padding: 8px 12px;
      border-radius: 999px;
      background: #eef4ff;
      color: var(--primary-dark);
      font-size: 13px;
      border: 1px solid #bfdbfe;
    }

    .footer {
      padding: 14px 24px 22px;
      color: var(--muted);
      font-size: 13px;
      text-align: center;
    }

    .error {
      color: var(--danger);
      font-weight: bold;
    }
  </style>
</head>
<body>
  <main class="page">
    <section class="app">
      <header class="header">
        <h1>MedBot</h1>
        <p>Asistente médico virtual basado en información verificada de MedlinePlus.</p>
      </header>

      <section class="content">
        <div class="notice">
          Esta herramienta brinda información educativa. No reemplaza la atención, diagnóstico ni tratamiento de un profesional de salud.
        </div>

        <div id="chat" class="chat">
          <div class="msg bot">
            <div class="bubble">
              Hola, soy MedBot. Escribe un tema de salud, por ejemplo: diabetes, asthma, hypertension, anemia o headache.
            </div>
          </div>
        </div>

        <form id="form" class="search-box">
          <input id="query" type="text" placeholder="Escribe tu consulta médica..." minlength="2" maxlength="120" autocomplete="off" />
          <button id="send" type="submit">Consultar</button>
        </form>

        <div class="examples">
          Ejemplos:
          <button type="button" onclick="quickSearch('diabetes')">diabetes</button>
          <button type="button" onclick="quickSearch('asthma')">asthma</button>
          <button type="button" onclick="quickSearch('hypertension')">hypertension</button>
          <button type="button" onclick="quickSearch('anemia')">anemia</button>
        </div>
      </section>

      <footer class="footer">
        Proyecto académico de Infraestructura como Código en AWS Cloud.
      </footer>
    </section>
  </main>

  <script>
    const chat = document.getElementById("chat");
    const form = document.getElementById("form");
    const input = document.getElementById("query");
    const send = document.getElementById("send");

    function addMessage(role, html) {
      const wrapper = document.createElement("div");
      wrapper.className = "msg " + role;

      const bubble = document.createElement("div");
      bubble.className = "bubble";
      bubble.innerHTML = html;

      wrapper.appendChild(bubble);
      chat.appendChild(wrapper);
      chat.scrollTop = chat.scrollHeight;
    }

    function escapeHtml(value) {
      return value
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#039;");
    }

    async function search(query) {
      const cleanQuery = query.trim();

      if (cleanQuery.length < 2) {
        addMessage("bot", "<span class='error'>Escribe al menos 2 caracteres.</span>");
        return;
      }

      addMessage("user", escapeHtml(cleanQuery));
      addMessage("bot", "Buscando información en el catálogo médico de MedlinePlus...");

      send.disabled = true;

      try {
        const response = await fetch(`/search?q=${encodeURIComponent(cleanQuery)}`);
        const data = await response.json();

        if (!response.ok) {
          throw new Error(data.detail || "No se pudo completar la consulta.");
        }

        let html = `<strong>${escapeHtml(data.message)}</strong>`;

        if (data.results.length > 0) {
          html += data.results.map((item) => `
            <div class="result-card">
              <h3>${escapeHtml(item.title)}</h3>
              <div class="summary">${item.summary}</div>
              <a href="${item.url}" target="_blank" rel="noopener noreferrer">Ver fuente en MedlinePlus</a>
            </div>
          `).join("");
        }

        html += `<p style="margin-top:12px;color:#667085;font-size:13px;">${escapeHtml(data.disclaimer)}</p>`;

        addMessage("bot", html);
      } catch (error) {
        addMessage("bot", `<span class="error">${escapeHtml(error.message)}</span>`);
      } finally {
        send.disabled = false;
      }
    }

    form.addEventListener("submit", (event) => {
      event.preventDefault();
      const value = input.value;
      input.value = "";
      search(value);
    });

    function quickSearch(value) {
      input.value = "";
      search(value);
    }
  </script>
</body>
</html>
"""


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
