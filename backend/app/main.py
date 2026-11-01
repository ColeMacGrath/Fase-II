"""API REST de la Capa Nube del Agente OS.

Servicio sin estado: no escribe en disco ni guarda el contenido de las
solicitudes. Los registros solo incluyen metadatos.
"""

import base64
import binascii
import logging
import time
import uuid
from functools import lru_cache

from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.responses import JSONResponse

from . import __version__
from .claude_client import Planner, PlannerError, build_planner
from .config import settings
from .guardrails import detect_injection, mask_pii
from .risk_model import get_classifier
from .schemas import (
    EXECUTABLE_ACTIONS,
    AnalyzeRequest,
    AnalyzeResponse,
    GuardRequest,
    GuardResponse,
    HealthResponse,
    PIIFinding,
    PlannedAction,
    RiskLevel,
    RiskRequest,
    RiskResponse,
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("agente-os")

app = FastAPI(
    title="Agente OS · Capa Nube",
    version=__version__,
    description=(
        "API del demo de Fase II. Recibe tareas y capturas ya anonimizadas por la app de macOS, "
        "aplica barreras deterministas, consulta a Claude para planear acciones y asigna un nivel "
        "de riesgo con un clasificador entrenado."
    ),
)


@lru_cache(maxsize=1)
def get_planner() -> Planner:
    return build_planner(settings)


def require_token(x_agent_token: str | None = Header(default=None)) -> None:
    if settings.agent_token and x_agent_token != settings.agent_token:
        raise HTTPException(status_code=401, detail="Token de agente inválido o ausente")


@app.exception_handler(PlannerError)
async def planner_error_handler(_: Request, exc: PlannerError) -> JSONResponse:
    log.warning("planner_error status=%s msg=%s", exc.status_code, exc)
    return JSONResponse(status_code=exc.status_code, content={"detail": str(exc)})


def _decode_image(image_b64: str) -> tuple[str, str]:
    if image_b64.startswith("data:"):
        image_b64 = image_b64.split(",", 1)[-1]
    try:
        raw = base64.b64decode(image_b64, validate=True)
    except (binascii.Error, ValueError):
        raise HTTPException(status_code=422, detail="image_base64 no es base64 válido")
    if len(raw) > settings.max_image_bytes:
        raise HTTPException(status_code=413, detail=f"La imagen excede {settings.max_image_bytes // (1024 * 1024)} MB")
    if raw.startswith(b"\x89PNG\r\n\x1a\n"):
        media = "image/png"
    elif raw.startswith(b"\xff\xd8\xff"):
        media = "image/jpeg"
    else:
        raise HTTPException(status_code=415, detail="Formato de imagen no soportado, usa PNG o JPEG")
    return base64.b64encode(raw).decode("ascii"), media


@app.get("/health", response_model=HealthResponse, tags=["sistema"])
def health() -> HealthResponse:
    clf = get_classifier()
    metrics = {k: float(v) for k, v in clf.metrics.items() if k in {"accuracy", "recall_alto", "precision_alto", "f1_macro"}}
    return HealthResponse(
        status="ok",
        service="agente-os-cloud",
        version=__version__,
        claude_mode=settings.claude_mode,
        claude_model=settings.claude_model if settings.claude_mode == "live" else "planificador-determinista",
        risk_model_version=clf.version,
        risk_model_metrics=metrics,
        auth_required=bool(settings.agent_token),
    )


@app.post("/v1/guard", response_model=GuardResponse, tags=["guardrails"], dependencies=[Depends(require_token)])
def guard(req: GuardRequest) -> GuardResponse:
    if len(req.text) > settings.max_screen_chars:
        raise HTTPException(status_code=413, detail=f"El texto excede {settings.max_screen_chars} caracteres")
    pii = mask_pii(req.text)
    inj = detect_injection(req.text)
    return GuardResponse(
        injection_detected=inj.detected,
        injection_score=inj.score,
        injection_matches=inj.matches,
        pii_found=[PIIFinding(kind=k, count=v) for k, v in sorted(pii.counts.items())],
        masked_text=pii.masked,
    )


@app.post("/v1/risk", response_model=RiskResponse, tags=["modelo"], dependencies=[Depends(require_token)])
def risk(req: RiskRequest) -> RiskResponse:
    if not req.description.strip():
        raise HTTPException(status_code=422, detail="La descripción no puede estar vacía")
    d = get_classifier().classify(req.description[:500], req.type)
    return RiskResponse(
        risk=d.level,
        model_prediction=d.model_level,
        model_confidence=d.confidence,
        probabilities=d.probabilities,
        rule_level=d.rule_level,
        rule_reason=d.rule_reason,
    )


@app.post("/v1/analyze", response_model=AnalyzeResponse, tags=["agente"], dependencies=[Depends(require_token)])
def analyze(req: AnalyzeRequest, planner: Planner = Depends(get_planner)) -> AnalyzeResponse:
    started = time.perf_counter()
    request_id = uuid.uuid4().hex[:12]

    task = req.task.strip()
    if not task:
        raise HTTPException(status_code=422, detail="La tarea no puede estar vacía")
    if len(task) > settings.max_task_chars:
        raise HTTPException(status_code=413, detail=f"La tarea excede {settings.max_task_chars} caracteres")
    if len(req.screen_text) > settings.max_screen_chars:
        raise HTTPException(status_code=413, detail=f"El texto de pantalla excede {settings.max_screen_chars} caracteres")

    image_b64, media_type = (None, None)
    if req.image_base64:
        image_b64, media_type = _decode_image(req.image_base64)

    # Segunda barrera del Filtro Ciego.
    task_pii = mask_pii(task)
    screen_pii = mask_pii(req.screen_text)
    pii_total = task_pii.total + screen_pii.total

    def respond(summary: str, actions: list[PlannedAction], blocked: bool, reasons: list[str], score: float, model: str) -> AnalyzeResponse:
        overall = RiskLevel.highest(RiskLevel.bajo, *(a.risk for a in actions))
        latency = int((time.perf_counter() - started) * 1000)
        log.info(
            "analyze id=%s mode=%s actions=%d risk=%s blocked=%s pii_server=%d latency_ms=%d",
            request_id, planner.mode, len(actions), overall.value, blocked, pii_total, latency,
        )
        return AnalyzeResponse(
            request_id=request_id, summary=summary, actions=actions, overall_risk=overall, blocked=blocked,
            block_reasons=reasons, pii_masked_server=pii_total, injection_score=score,
            claude_mode=planner.mode, model=model, latency_ms=latency,
        )

    # Validador contra inyección: si la pantalla trae órdenes para el agente, no se consulta a Claude.
    injection = detect_injection(req.screen_text)
    if injection.detected:
        reasons = [f"Posible inyección de prompt en pantalla: {m}" for m in injection.matches]
        return respond("Ejecución cancelada: la pantalla contiene instrucciones dirigidas al agente.", [], True, reasons, injection.score, planner.model)

    plan = planner.plan(task_pii.masked, screen_pii.masked, image_b64, media_type, req.app_context)

    if plan.screen_injection_suspected:
        return respond(
            "Ejecución cancelada: Claude detectó instrucciones sospechosas en la pantalla.",
            [], True, ["Claude marcó el contenido de pantalla como posible inyección"], max(injection.score, 0.5), plan.model,
        )

    clf = get_classifier()
    actions: list[PlannedAction] = []
    for a in plan.actions:
        decision = clf.classify(f"{a['description']} {a['target']}".strip(), a["type"])
        is_exec = a["type"] in EXECUTABLE_ACTIONS and decision.level is not RiskLevel.alto
        actions.append(PlannedAction(
            type=a["type"], description=a["description"], target=a["target"], content=mask_pii(a["content"]).masked,
            risk=decision.level, risk_sources=decision.sources, model_confidence=decision.confidence,
            executable=is_exec, requires_biometric=decision.level is RiskLevel.alto, simulated=not is_exec,
        ))

    return respond(plan.summary, actions, False, [], injection.score, plan.model)
