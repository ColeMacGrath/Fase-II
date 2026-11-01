"""Contratos de la API REST compartidos con la app de macOS."""

from enum import Enum
from typing import Literal

from pydantic import BaseModel, Field


class RiskLevel(str, Enum):
    bajo = "bajo"
    medio = "medio"
    alto = "alto"

    @property
    def rank(self) -> int:
        return {"bajo": 0, "medio": 1, "alto": 2}[self.value]

    @staticmethod
    def highest(*levels: "RiskLevel") -> "RiskLevel":
        return max(levels, key=lambda lvl: lvl.rank)


ActionType = Literal[
    "open_url",
    "open_app",
    "copy_to_clipboard",
    "save_text_file",
    "delete_file",
    "send_message",
    "payment",
    "modify_record",
    "run_command",
    "other",
]

# Acciones que la app puede ejecutar de verdad. Todo lo demás se simula.
EXECUTABLE_ACTIONS: set[str] = {"open_url", "open_app", "copy_to_clipboard", "save_text_file"}


class AnalyzeRequest(BaseModel):
    task: str = Field(..., description="Instrucción del usuario en lenguaje natural")
    screen_text: str = Field("", description="Texto de pantalla obtenido por OCR y enmascarado en local")
    image_base64: str | None = Field(None, description="Captura enmascarada en PNG o JPEG codificada en base64")
    app_context: str | None = Field(None, description="Aplicación activa o contexto adicional")


class PlannedAction(BaseModel):
    type: ActionType
    description: str
    target: str = ""
    content: str = ""
    risk: RiskLevel
    risk_sources: dict[str, str] = Field(default_factory=dict)
    model_confidence: float = 0.0
    executable: bool
    requires_biometric: bool
    simulated: bool


class AnalyzeResponse(BaseModel):
    request_id: str
    summary: str
    actions: list[PlannedAction]
    overall_risk: RiskLevel
    blocked: bool
    block_reasons: list[str]
    pii_masked_server: int
    injection_score: float
    claude_mode: str
    model: str
    latency_ms: int


class RiskRequest(BaseModel):
    description: str
    type: ActionType | None = Field(None, description="Tipo de acción; si se omite solo se evalúan el modelo y las palabras clave")


class RiskResponse(BaseModel):
    risk: RiskLevel
    model_prediction: RiskLevel
    model_confidence: float
    probabilities: dict[str, float]
    rule_level: RiskLevel
    rule_reason: str


class GuardRequest(BaseModel):
    text: str


class PIIFinding(BaseModel):
    kind: str
    count: int


class GuardResponse(BaseModel):
    injection_detected: bool
    injection_score: float
    injection_matches: list[str]
    pii_found: list[PIIFinding]
    masked_text: str


class HealthResponse(BaseModel):
    status: Literal["ok"]
    service: str
    version: str
    claude_mode: str
    claude_model: str
    risk_model_version: str
    risk_model_metrics: dict[str, float]
    auth_required: bool
