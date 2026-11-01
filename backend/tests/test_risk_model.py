"""Validación del clasificador de riesgo con frases escritas a mano."""

import csv

from conftest import DATA

from app.risk_model import get_classifier
from app.schemas import RiskLevel


def _holdout():
    return list(csv.DictReader(open(DATA / "risk_holdout.csv", encoding="utf-8")))


def test_el_modelo_carga_y_predice_probabilidades():
    clf = get_classifier()
    d = clf.classify("Abrir Safari", "open_app")
    assert abs(sum(d.probabilities.values()) - 1.0) < 1e-3
    assert set(d.probabilities) == {"bajo", "medio", "alto"}


def test_holdout_exactitud_del_modelo_solo():
    rows = _holdout()
    clf = get_classifier()
    acc = sum(clf.classify(r["description"]).model_level.value == r["label"] for r in rows) / len(rows)
    assert acc >= 0.80


def test_sistema_combinado_no_deja_pasar_riesgo_alto():
    """KPI de Fase I: cero acciones críticas sin confirmación. Recall de 'alto' debe ser 1.0."""
    clf = get_classifier()
    altos = [r for r in _holdout() if r["label"] == "alto"]
    missed = [r["description"] for r in altos if clf.classify(r["description"]).level is not RiskLevel.alto]
    assert missed == []


def test_las_reglas_nunca_bajan_un_riesgo():
    clf = get_classifier()
    for t in ["delete_file", "send_message", "payment", "modify_record", "run_command"]:
        assert clf.classify("Abrir Safari", t).level is RiskLevel.alto


def test_errores_del_sistema_solo_escalan():
    """Cuando el sistema se equivoca, debe ser hacia un nivel más alto, que es el lado seguro."""
    clf = get_classifier()
    order = {"bajo": 0, "medio": 1, "alto": 2}
    for r in _holdout():
        pred = clf.classify(r["description"]).level.value
        assert order[pred] >= order[r["label"]], r["description"]
