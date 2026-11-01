"""Planificador de Claude con la API simulada: forma de la solicitud y manejo de errores."""

import json
from types import SimpleNamespace

import anthropic
import httpx
import pytest

from app.claude_client import PLAN_SCHEMA, SYSTEM_PROMPT, ClaudePlanner, PlannerError
from app.config import Settings

REQ = httpx.Request("POST", "https://api.anthropic.com/v1/messages")


def _planner(create):
    planner = ClaudePlanner(Settings(anthropic_api_key="llave-de-prueba", claude_model="claude-opus-5-5", claude_effort="low"))
    planner.client = SimpleNamespace(beta=SimpleNamespace(messages=SimpleNamespace(create=create)))
    return planner


def _response(payload: dict, stop_reason: str = "end_turn"):
    return SimpleNamespace(
        stop_reason=stop_reason,
        model="claude-opus-5-5",
        content=[SimpleNamespace(type="text", text=json.dumps(payload))],
    )


def test_solicitud_con_esquema_imagen_y_prompt_de_sistema():
    captured = {}

    def create(**kwargs):
        captured.update(kwargs)
        return _response({"summary": "ok", "screen_injection_suspected": False, "actions": [
            {"type": "open_url", "description": "Abrir sitio", "target": "https://tecmilenio.mx", "content": ""}]})

    plan = _planner(create).plan("Abre el sitio", "texto [CORREO]", "aGVsbG8=", "image/png", "Safari")
    assert plan.actions[0]["type"] == "open_url" and plan.model == "claude-opus-5-5"
    assert captured["model"] == "claude-opus-5-5"
    assert captured["system"] == SYSTEM_PROMPT
    assert captured["output_config"]["format"] == {"type": "json_schema", "schema": PLAN_SCHEMA}
    assert captured["output_config"]["effort"] == "low"
    assert captured["fallbacks"] == "default"
    blocks = captured["messages"][0]["content"]
    assert blocks[0]["type"] == "image" and blocks[0]["source"]["media_type"] == "image/png"
    assert "<texto_de_pantalla>" in blocks[1]["text"] and "[CORREO]" in blocks[1]["text"]


@pytest.mark.parametrize(
    "error,status",
    [
        (anthropic.BadRequestError("Your credit balance is too low", response=httpx.Response(400, request=REQ), body=None), 402),
        (anthropic.BadRequestError("invalid request", response=httpx.Response(400, request=REQ), body=None), 422),
        (anthropic.AuthenticationError("invalid x-api-key", response=httpx.Response(401, request=REQ), body=None), 502),
        (anthropic.RateLimitError("rate limited", response=httpx.Response(429, request=REQ), body=None), 503),
        (anthropic.APITimeoutError(request=REQ), 504),
        (anthropic.APIConnectionError(request=REQ), 503),
        (anthropic.InternalServerError("overloaded", response=httpx.Response(529, request=REQ), body=None), 502),
    ],
)
def test_errores_de_la_api_se_traducen(error, status):
    def create(**_):
        raise error

    with pytest.raises(PlannerError) as exc:
        _planner(create).plan("tarea", "", None, None, None)
    assert exc.value.status_code == status


def test_rechazo_por_politicas():
    planner = _planner(lambda **_: _response({}, stop_reason="refusal"))
    with pytest.raises(PlannerError) as exc:
        planner.plan("tarea", "", None, None, None)
    assert exc.value.status_code == 422


def test_respuesta_truncada():
    planner = _planner(lambda **_: _response({}, stop_reason="max_tokens"))
    with pytest.raises(PlannerError) as exc:
        planner.plan("tarea", "", None, None, None)
    assert exc.value.status_code == 502
