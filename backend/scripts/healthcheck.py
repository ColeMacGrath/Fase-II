"""Chequeo de salud del contenedor: termina con 0 si /health responde 200."""

import os
import sys
import urllib.request

PORT = os.getenv("PORT", "8000")

try:
    with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/health", timeout=2) as r:
        sys.exit(0 if r.status == 200 else 1)
except Exception:
    sys.exit(1)
