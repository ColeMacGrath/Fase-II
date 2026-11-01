"""Barreras deterministas de la Capa Nube.

1. Filtro de PII: segunda barrera. La app ya enmascara en local; si algo llega
   sin enmascarar, se tapa aquí antes de enviarlo a Claude y se cuenta.
2. Detector de inyección de prompts sobre el texto que aparece en pantalla.
"""

import re
import unicodedata
from dataclasses import dataclass

# ---------------------------------------------------------------- PII


def _luhn_ok(digits: str) -> bool:
    total, parity = 0, len(digits) % 2
    for i, ch in enumerate(digits):
        d = int(ch)
        if i % 2 == parity:
            d *= 2
            if d > 9:
                d -= 9
        total += d
    return total % 10 == 0


def _clabe_ok(digits: str) -> bool:
    if len(digits) != 18:
        return False
    weights = [3, 7, 1] * 6
    s = sum((int(d) * w) % 10 for d, w in zip(digits[:17], weights))
    return (10 - s % 10) % 10 == int(digits[17])


_CURP = re.compile(r"\b[A-Z][AEIOUX][A-Z]{2}\d{6}[HMX][A-Z]{5}[A-Z0-9]\d\b", re.I)
_RFC = re.compile(r"\b[A-ZÑ&]{3,4}\d{6}[A-Z0-9]{3}\b", re.I)
_EMAIL = re.compile(r"\b[\w.+-]+@[\w-]+(?:\.[\w-]+)+\b")
_DIGIT_RUN = re.compile(r"(?<![\w])(?:\+?\d[\d \-.]{8,24}\d)(?![\w])")


@dataclass
class PIIResult:
    masked: str
    counts: dict[str, int]

    @property
    def total(self) -> int:
        return sum(self.counts.values())


def mask_pii(text: str) -> PIIResult:
    counts: dict[str, int] = {}

    def bump(kind: str) -> None:
        counts[kind] = counts.get(kind, 0) + 1

    def sub_simple(pattern: re.Pattern, kind: str, token: str, value: str) -> str:
        def repl(_m: re.Match) -> str:
            bump(kind)
            return token

        return pattern.sub(repl, value)

    out = sub_simple(_CURP, "curp", "[CURP]", text)
    out = sub_simple(_RFC, "rfc", "[RFC]", out)
    out = sub_simple(_EMAIL, "correo", "[CORREO]", out)

    def digits_repl(m: re.Match) -> str:
        raw = m.group(0)
        digits = re.sub(r"\D", "", raw)
        if 13 <= len(digits) <= 19 and _luhn_ok(digits):
            bump("tarjeta")
            return "[TARJETA]"
        if _clabe_ok(digits):
            bump("clabe")
            return "[CLABE]"
        if len(digits) == 10 or (len(digits) == 12 and digits.startswith("52")):
            bump("telefono")
            return "[TELEFONO]"
        return raw

    out = _DIGIT_RUN.sub(digits_repl, out)
    return PIIResult(masked=out, counts=counts)


# ---------------------------------------------------------- Inyección

_ZERO_WIDTH = re.compile(r"[​-‏⁠﻿]")

# (patrón, peso). Se evalúa sobre texto en minúsculas y sin acentos.
_AGENT = r"(asistente|agente|ia|ai|llm|assistant|agent|bot|robot|modelo|model|chatbot)"
_INJECTION_PATTERNS: list[tuple[str, float]] = [
    # Anular instrucciones o reglas previas.
    (r"\b(ignora|olvida|omite|descarta|ignore|forget|disregard|override)\b.{0,40}\b(instruccion\w*|indicacion\w*|reglas|tarea|solicitud|lo que te pidio|lo anterior|todo|everything|above|instructions|rules|prompt|guidelines|task|request|safety)", 0.8),
    (r"\b(nuevas|new|updated|actualizadas)\s+(instrucciones|instructions|orders|ordenes|task|tarea)\b|\b(your new task|tu nueva tarea)\b", 0.6),
    (r"\b(system prompt|prompt del sistema|instrucciones del sistema|system override|developer mode|modo desarrollador|jailbreak)\b", 0.7),
    (r"\b(ahora eres|a partir de ahora eres|you are now|from now on you are|act as|actua como|pretend you are|finge que eres)\b", 0.4),
    # Texto dirigido explícitamente al agente.
    (rf"\b(para|for|to|attention|atencion|dear|querido|querida|hey|hola|nota para|mensaje para|a cualquier|any)\s+(el |la |the |un |una |an? )?{_AGENT}\b", 0.5),
    (rf"^\W*{_AGENT}(\s+(de ia|de ai|virtual|automatico|automatizado))?\s*[:,]", 0.5),
    (rf"\b(si eres|if you are|cuando|when|si)\s+(un |una |an? )?{_AGENT}\b", 0.5),
    (rf"\b{_AGENT}\b.{{0,40}}\b(debes|debe|deberia|tienes que|tiene que|must|should|shall|have to|necesitas)\b", 0.5),
    (r"\b(te autoriz\w*|tienes permiso|usuario autoriz\w*|authorized you|you are authorized|you have permission)\b", 0.5),
    # Acciones peligrosas.
    (r"\b(transfiere|transferir|deposita|envia|paga|wire|transfer|send|pay)\b.{0,40}\b(fondos|dinero|pesos|dolares|usd|mxn|funds|money|bitcoin|btc|\$\s?\d)", 0.4),
    (r"\b(borra|elimina|delete|remove|wipe|formatea|format)\b.{0,30}\b(todos|todo|all|every|entire|disco|disk|archivos|files|carpeta|folder|base de datos|database|logs|respaldos)\b", 0.5),
    (r"rm\s+-rf|del\s+/[sq]|format\s+c:|sudo\s+", 0.7),
    (r"\b(envia|manda|comparte|revela|escribe|ingresa|send|share|reveal|leak|forward|email|write|type|exfiltra|exfiltrate)\b.{0,40}\b(contrasena|contrasenas|password|passwords|credenciales|credentials|token|tokens|api key|llave|claves)\b", 0.7),
    # Evadir al usuario o la confirmación.
    (r"\b(no le digas|sin avisar|no informes|sin que el usuario|sin preguntar|do not tell|don't tell|without telling|without the user|silently|en secreto)\b", 0.6),
    (r"\b(confirma automaticamente|aprueba automaticamente|auto-?approve|skip confirmation|no need to confirm|omite la confirmacion|sin confirmacion)\b", 0.6),
    (r"<\s*/?\s*(system|instructions|admin)\s*>|\[\s*/?\s*(system|inst)\s*\]|###\s*(system|instruction)", 0.7),
]
_COMPILED = [(re.compile(p, re.M), w) for p, w in _INJECTION_PATTERNS]
INJECTION_THRESHOLD = 0.5


def _normalize(text: str) -> str:
    text = _ZERO_WIDTH.sub("", text)
    text = unicodedata.normalize("NFKD", text)
    text = "".join(c for c in text if not unicodedata.combining(c))
    return re.sub(r"\s+", " ", text.lower())


@dataclass
class InjectionResult:
    detected: bool
    score: float
    matches: list[str]


def detect_injection(text: str) -> InjectionResult:
    if not text:
        return InjectionResult(False, 0.0, [])
    norm = _normalize(text)
    score, matches = 0.0, []
    for pattern, weight in _COMPILED:
        m = pattern.search(norm)
        if m:
            score += weight
            matches.append(m.group(0)[:80])
    if _ZERO_WIDTH.search(text):
        score += 0.3
        matches.append("caracteres invisibles")
    score = round(min(score, 1.0), 2)
    return InjectionResult(score >= INJECTION_THRESHOLD, score, matches)
