"""Configuración del servicio leída de variables de entorno."""

import os
from dataclasses import dataclass, field
from pathlib import Path


def _int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, default))
    except ValueError:
        return default


@dataclass(frozen=True)
class Settings:
    anthropic_api_key: str = field(default_factory=lambda: os.getenv("ANTHROPIC_API_KEY", "").strip())
    claude_model: str = field(default_factory=lambda: os.getenv("CLAUDE_MODEL", "claude-opus-5-5"))
    claude_effort: str = field(default_factory=lambda: os.getenv("CLAUDE_EFFORT", "low"))
    claude_timeout_s: int = field(default_factory=lambda: _int("CLAUDE_TIMEOUT_S", 60))
    agent_token: str = field(default_factory=lambda: os.getenv("AGENT_TOKEN", "").strip())
    force_mock: bool = field(default_factory=lambda: os.getenv("CLAUDE_MOCK", "0") == "1")
    max_task_chars: int = field(default_factory=lambda: _int("MAX_TASK_CHARS", 2000))
    max_screen_chars: int = field(default_factory=lambda: _int("MAX_SCREEN_CHARS", 20000))
    max_image_bytes: int = field(default_factory=lambda: _int("MAX_IMAGE_BYTES", 5 * 1024 * 1024))
    model_dir: Path = field(default_factory=lambda: Path(os.getenv("MODEL_DIR", Path(__file__).resolve().parent.parent / "model")))

    @property
    def claude_mode(self) -> str:
        return "live" if self.anthropic_api_key and not self.force_mock else "mock"


settings = Settings()
