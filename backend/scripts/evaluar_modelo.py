"""Evaluación del modelo y de las barreras con los sets independientes.

Imprime un reporte en texto y, si se pasa una ruta, guarda las métricas en JSON.
Uso: python scripts/evaluar_modelo.py [salida.json]
"""

import csv
import json
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from app.guardrails import detect_injection, mask_pii  # noqa: E402
from app.risk_model import get_classifier  # noqa: E402

DATA = ROOT / "tests" / "data"
LABELS = ["bajo", "medio", "alto"]


def confusion(y_true, y_pred):
    m = [[0] * 3 for _ in range(3)]
    for t, p in zip(y_true, y_pred):
        m[LABELS.index(t)][LABELS.index(p)] += 1
    return m


def per_class(m):
    out = {}
    for i, lbl in enumerate(LABELS):
        tp = m[i][i]
        fn = sum(m[i]) - tp
        fp = sum(m[r][i] for r in range(3)) - tp
        out[lbl] = {
            "precision": round(tp / (tp + fp), 4) if tp + fp else 0.0,
            "recall": round(tp / (tp + fn), 4) if tp + fn else 0.0,
        }
    return out


def main():
    clf = get_classifier()
    rows = list(csv.DictReader(open(DATA / "risk_holdout.csv", encoding="utf-8")))
    y = [r["label"] for r in rows]

    t0 = time.perf_counter()
    decisions = [clf.classify(r["description"]) for r in rows]
    ms_per = (time.perf_counter() - t0) * 1000 / len(rows)

    model_pred = [d.model_level.value for d in decisions]
    system_pred = [d.level.value for d in decisions]
    m_model, m_system = confusion(y, model_pred), confusion(y, system_pred)
    acc = lambda p: round(sum(a == b for a, b in zip(y, p)) / len(y), 4)  # noqa: E731
    order = {"bajo": 0, "medio": 1, "alto": 2}
    under = sum(order[p] < order[t] for t, p in zip(y, system_pred))

    def injection(path):
        data = list(csv.DictReader(open(path, encoding="utf-8")))
        atk = [r for r in data if r["label"] == "1"]
        ben = [r for r in data if r["label"] == "0"]
        det = sum(detect_injection(r["text"]).detected for r in atk)
        fp = sum(detect_injection(r["text"]).detected for r in ben)
        return {"ataques": len(atk), "detectados": det, "tasa_deteccion": round(det / len(atk), 4),
                "benignos": len(ben), "falsos_positivos": fp, "tasa_fp": round(fp / len(ben), 4)}

    pii_cases = {
        "tarjeta": "4111 1111 1111 1111", "clabe": "002180001234567896", "rfc": "GOCM800101AB1",
        "curp": "GOCM800101HDFRRS09", "correo": "ana@empresa.mx", "telefono": "81 1234 5678",
    }
    pii_ok = {k: mask_pii(f"dato {v} fin").counts.get(k, 0) == 1 for k, v in pii_cases.items()}

    report = {
        "modelo_version": clf.version,
        "metricas_entrenamiento": {k: clf.metrics.get(k) for k in ["n_total", "n_train", "n_test", "accuracy", "recall_alto", "f1_macro", "split"]},
        "holdout_riesgo": {
            "n": len(rows),
            "modelo_solo": {"accuracy": acc(model_pred), "por_clase": per_class(m_model), "matriz": m_model},
            "sistema_modelo_mas_reglas": {"accuracy": acc(system_pred), "por_clase": per_class(m_system), "matriz": m_system,
                                          "errores_que_bajan_riesgo": under},
            "latencia_ms_por_clasificacion": round(ms_per, 3),
        },
        "inyeccion_red_team": injection(DATA / "injection_redteam.csv"),
        "inyeccion_holdout": injection(DATA / "injection_holdout.csv"),
        "pii_por_tipo": pii_ok,
    }

    h = report["holdout_riesgo"]
    print(f"Modelo de riesgo: {clf.version}")
    print(f"Entrenamiento sintético (prueba por marcos no vistos): accuracy={clf.metrics.get('accuracy')} recall_alto={clf.metrics.get('recall_alto')}")
    print(f"\nHoldout escrito a mano ({h['n']} frases)")
    print(f"  Modelo solo:          accuracy={h['modelo_solo']['accuracy']}  recall_alto={h['modelo_solo']['por_clase']['alto']['recall']}")
    print(f"  Modelo + reglas:      accuracy={h['sistema_modelo_mas_reglas']['accuracy']}  recall_alto={h['sistema_modelo_mas_reglas']['por_clase']['alto']['recall']}")
    print(f"  Errores que bajan el riesgo: {under}")
    print(f"  Matriz del sistema (filas real, columnas predicho; bajo, medio, alto): {h['sistema_modelo_mas_reglas']['matriz']}")
    print(f"  Latencia media por clasificación: {h['latencia_ms_por_clasificacion']} ms")
    for name in ["inyeccion_red_team", "inyeccion_holdout"]:
        r = report[name]
        print(f"\n{name}: detección {r['detectados']}/{r['ataques']} = {r['tasa_deteccion']:.1%}, falsos positivos {r['falsos_positivos']}/{r['benignos']}")
    print(f"\nPII por tipo detectado correctamente: {pii_ok}")

    if len(sys.argv) > 1:
        Path(sys.argv[1]).write_text(json.dumps(report, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
