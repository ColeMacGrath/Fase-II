"""Semáforo de riesgo de tres niveles.

El nivel final es el mayor entre el clasificador entrenado y las reglas
deterministas. Ni el clasificador ni Claude pueden bajar un riesgo que las
reglas marcan como alto.
"""

import json
import pickle
import re
import unicodedata
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

from .config import settings
from .schemas import RiskLevel

TYPE_RULES: dict[str, RiskLevel] = {
    "open_url": RiskLevel.bajo,
    "open_app": RiskLevel.bajo,
    "copy_to_clipboard": RiskLevel.bajo,
    "save_text_file": RiskLevel.medio,
    "other": RiskLevel.medio,
    "delete_file": RiskLevel.alto,
    "send_message": RiskLevel.alto,
    "payment": RiskLevel.alto,
    "modify_record": RiskLevel.alto,
    "run_command": RiskLevel.alto,
}

_HIGH_KEYWORDS = re.compile(
    r"\b(borr(?:a|ar|e|en|alo|ala|alos|alas|ando)|elimin\w*|delete\w*|remove|vacia\w*|pag\w*|pay\w*|transfer\w*|wire|deposit\w*|"
    r"compra\w*|purchase|envi\w*|send\w*|manda\w*|public\w*|firm\w*|sign|aprob\w*|approve\w*|"
    r"contrasena\w*|password\w*|sudo|rm -rf|ejecut\w* (un )?comando|run command|base de datos|database|"
    r"saldo|revoc\w*|cancel\w*|overwrite|sobrescrib\w*|dar de baja)\b"
)


def _normalize(text: str) -> str:
    text = unicodedata.normalize("NFKD", text.lower())
    return "".join(c for c in text if not unicodedata.combining(c))


@dataclass
class RiskDecision:
    level: RiskLevel
    model_level: RiskLevel
    confidence: float
    probabilities: dict[str, float]
    rule_level: RiskLevel
    rule_reason: str

    @property
    def sources(self) -> dict[str, str]:
        return {"modelo": self.model_level.value, "reglas": self.rule_level.value, "motivo_regla": self.rule_reason}


class RiskClassifier:
    def __init__(self, model_dir: Path):
        with open(model_dir / "model.pkl", "rb") as f:
            artifact = pickle.load(f)
        self.pipeline = artifact["pipeline"]
        self.version: str = artifact["version"]
        metrics_path = model_dir / "metrics.json"
        self.metrics: dict = json.loads(metrics_path.read_text()) if metrics_path.exists() else {}

    def rule_level(self, description: str, action_type: str | None) -> tuple[RiskLevel, str]:
        if action_type is None:
            by_type, reason = RiskLevel.bajo, "sin tipo de acción"
        else:
            by_type = TYPE_RULES.get(action_type, RiskLevel.medio)
            reason = f"tipo {action_type}"
        if by_type is not RiskLevel.alto:
            m = _HIGH_KEYWORDS.search(_normalize(description))
            if m:
                return RiskLevel.alto, f"palabra clave '{m.group(0)}'"
        return by_type, reason

    def classify(self, description: str, action_type: str | None = None) -> RiskDecision:
        proba = self.pipeline.predict_proba([description])[0]
        classes = list(self.pipeline.classes_)
        probabilities = {c: round(float(p), 4) for c, p in zip(classes, proba)}
        best = max(probabilities, key=probabilities.get)
        model_level = RiskLevel(best)
        rule, reason = self.rule_level(description, action_type)
        return RiskDecision(
            level=RiskLevel.highest(model_level, rule),
            model_level=model_level,
            confidence=probabilities[best],
            probabilities=probabilities,
            rule_level=rule,
            rule_reason=reason,
        )


@lru_cache(maxsize=1)
def get_classifier() -> RiskClassifier:
    return RiskClassifier(settings.model_dir)
