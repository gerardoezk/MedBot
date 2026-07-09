import sys
from pathlib import Path

import pytest
from fastapi import HTTPException

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "app" / "src"))

import main


def test_health_returns_ok():
    assert main.health() == {"status": "ok"}


def test_home_contains_medbot_title():
    html = main.home()
    assert "MedBot" in html
    assert "Asistente" in html


class DummyCursor:
    def __init__(self):
        self.executed = False

    def execute(self, query, params):
        self.executed = True
        self.params = params

    def fetchall(self):
        return [
            (
                "Diabetes",
                "https://medlineplus.gov/spanish/diabetes.html",
                "La diabetes es una enfermedad relacionada con el azúcar en la sangre.",
                0.87,
            )
        ]

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, traceback):
        return False


class DummyConnection:
    def __init__(self):
        self.cursor_obj = DummyCursor()
        self.closed = False

    def cursor(self):
        return self.cursor_obj

    def close(self):
        self.closed = True


def test_search_returns_medlineplus_result(monkeypatch):
    dummy_connection = DummyConnection()

    def fake_conn():
        return dummy_connection

    monkeypatch.setattr(main, "_conn", fake_conn)

    response = main.search(" diabetes ")

    assert response["query"] == "diabetes"
    assert response["count"] == 1
    assert response["results"][0]["title"] == "Diabetes"
    assert response["results"][0]["source"] == "MedlinePlus"
    assert response["disclaimer"] == main.DISCLAIMER
    assert dummy_connection.closed is True


def test_search_handles_database_error(monkeypatch):
    import psycopg2

    def fake_conn():
        raise psycopg2.OperationalError("database unavailable")

    monkeypatch.setattr(main, "_conn", fake_conn)

    with pytest.raises(HTTPException) as exc_info:
        main.search("diabetes")

    assert exc_info.value.status_code == 503
    assert "base de datos" in exc_info.value.detail
