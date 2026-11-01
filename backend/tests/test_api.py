"""Pruebas funcionales de los endpoints."""

PNG_1PX = (
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
)


def test_health_reporta_estado_y_modelo(client):
    r = client.get("/health")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok"
    assert body["claude_mode"] == "mock"
    assert body["risk_model_version"].startswith("risk-")
    assert body["risk_model_metrics"]["accuracy"] > 0.9


def test_openapi_documenta_los_endpoints(client):
    paths = client.get("/openapi.json").json()["paths"]
    assert {"/health", "/v1/analyze", "/v1/risk", "/v1/guard"} <= set(paths)


def test_guard_enmascara_y_detecta(client):
    r = client.post("/v1/guard", json={"text": "Mi correo es ana@empresa.mx y mi tarjeta 4111 1111 1111 1111"})
    assert r.status_code == 200
    body = r.json()
    assert "[CORREO]" in body["masked_text"] and "[TARJETA]" in body["masked_text"]
    assert {f["kind"] for f in body["pii_found"]} == {"correo", "tarjeta"}
    assert body["injection_detected"] is False


def test_risk_clasifica_niveles(client):
    assert client.post("/v1/risk", json={"description": "Abrir Safari", "type": "open_app"}).json()["risk"] == "bajo"
    assert client.post("/v1/risk", json={"description": "Guardar el reporte en un archivo", "type": "save_text_file"}).json()["risk"] == "medio"
    alto = client.post("/v1/risk", json={"description": "Transferir 5000 pesos al proveedor", "type": "payment"}).json()
    assert alto["risk"] == "alto" and alto["rule_level"] == "alto"


def test_analyze_flujo_completo_bajo_riesgo(client):
    r = client.post("/v1/analyze", json={"task": "Abre https://www.tecmilenio.mx y copia el texto", "screen_text": "Bienvenido"})
    assert r.status_code == 200
    body = r.json()
    assert body["blocked"] is False
    types = [a["type"] for a in body["actions"]]
    assert "open_url" in types and "copy_to_clipboard" in types
    for a in body["actions"]:
        assert a["risk"] in {"bajo", "medio"}
        assert a["executable"] is True and a["requires_biometric"] is False
    assert body["latency_ms"] >= 0 and len(body["request_id"]) == 12


def test_analyze_accion_critica_requiere_biometria(client):
    body = client.post("/v1/analyze", json={"task": "Paga la factura del proveedor"}).json()
    pay = [a for a in body["actions"] if a["type"] == "payment"]
    assert pay and pay[0]["risk"] == "alto"
    assert pay[0]["requires_biometric"] is True and pay[0]["executable"] is False and pay[0]["simulated"] is True
    assert body["overall_risk"] == "alto"


def test_analyze_acepta_imagen_png(client):
    r = client.post("/v1/analyze", json={"task": "Copia el texto de la captura", "image_base64": PNG_1PX})
    assert r.status_code == 200


def test_token_de_agente(client, monkeypatch):
    from app import main

    monkeypatch.setattr(main, "settings", main.settings.__class__(agent_token="secreto"))
    assert client.post("/v1/guard", json={"text": "hola"}).status_code == 401
    assert client.post("/v1/guard", json={"text": "hola"}, headers={"X-Agent-Token": "malo"}).status_code == 401
    assert client.post("/v1/guard", json={"text": "hola"}, headers={"X-Agent-Token": "secreto"}).status_code == 200
