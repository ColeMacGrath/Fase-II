"""Configuración común de pytest.

Las pruebas corren siempre con el planificador determinista, sin llave de API y sin token, para
que sean reproducibles y gratuitas. Si no existe model.pkl (por ejemplo al
correr fuera de Docker), se entrena en un directorio temporal.
"""

import os
import subprocess
import sys
import tempfile
from pathlib import Path

BACKEND = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND))

os.environ["CLAUDE_MOCK"] = "1"
os.environ["AGENT_TOKEN"] = ""
_default_model_dir = Path(os.environ.get("MODEL_DIR", BACKEND / "model"))
if not (_default_model_dir / "model.pkl").exists():
    tmp = Path(tempfile.mkdtemp(prefix="riskmodel-"))
    subprocess.run([sys.executable, str(BACKEND / "model" / "train_risk_model.py"), str(tmp)], check=True, capture_output=True)
    os.environ["MODEL_DIR"] = str(tmp)

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.main import app, get_planner  # noqa: E402

DATA = Path(__file__).resolve().parent / "data"


@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()


@pytest.fixture
def override_planner():
    def _set(planner):
        app.dependency_overrides[get_planner] = lambda: planner
        return planner

    yield _set
    app.dependency_overrides.clear()
