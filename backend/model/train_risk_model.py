"""Entrena el clasificador del semáforo de riesgo y lo guarda como model.pkl.

Sigue el patrón del Tema 15: entrenamiento offline, artefacto serializado y
uso posterior desde la API. El dataset es sintético y se genera con semilla
fija para que el build de Docker sea reproducible.

El generador es composicional: cada ejemplo combina una acción del léxico de
su nivel de riesgo, un objeto y un marco de frase. La evaluación se hace con
marcos que el modelo no vio durante el entrenamiento.

Uso: python model/train_risk_model.py [directorio_salida]
"""

import csv
import json
import pickle
import random
import sys
from datetime import datetime, timezone
from pathlib import Path

import sklearn
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix
from sklearn.model_selection import GroupShuffleSplit
from sklearn.pipeline import FeatureUnion, Pipeline

SEED = 42
MODEL_VERSION = "risk-tfidf-lr-1.1"
LABELS = ["bajo", "medio", "alto"]

# Léxico de acciones por nivel. {o} es el objeto de la acción.
ACTIONS = {
    "bajo": [
        "abrir {o}", "abre {o}", "open {o}", "mostrar {o}", "muestra {o}", "show {o}", "ver {o}", "view {o}",
        "leer {o}", "lee {o}", "read {o}", "buscar {o}", "busca {o}", "search for {o}", "find {o}",
        "consultar {o}", "consulta {o}", "copiar {o} al portapapeles", "copia {o}", "copy {o}",
        "resumir {o}", "resume {o}", "summarize {o}", "revisar {o}", "revisa {o}", "review {o}",
        "seleccionar {o}", "selecciona {o}", "select {o}", "resaltar {o}", "highlight {o}",
        "traducir {o}", "traduce {o}", "translate {o}", "contar las filas de {o}", "extraer los datos de {o}",
        "navegar a {o}", "ir a {o}", "go to {o}", "hacer scroll hasta {o}", "comparar {o} con el mes pasado",
    ],
    "medio": [
        "guardar {o} en un archivo", "guarda {o}", "save {o}", "descargar {o}", "descarga {o}", "download {o}",
        "renombrar {o}", "renombra {o}", "rename {o}", "mover {o} a otra carpeta", "mueve {o}", "move {o}",
        "exportar {o} a CSV", "exporta {o}", "export {o}", "crear un borrador con {o}", "redacta un borrador sobre {o}",
        "draft a reply about {o}", "llenar el formulario de {o} sin enviarlo", "agendar una reunión sobre {o}",
        "crear un recordatorio de {o}", "schedule a reminder for {o}", "duplicar {o}", "duplicate {o}",
        "archivar {o}", "archive {o}", "etiquetar {o}", "comprimir {o}", "adjuntar {o} al borrador",
        "crear una carpeta para {o}", "agregar una nota a {o}", "cambiar el formato de {o}", "instalar una extensión para {o}",
    ],
    "alto": [
        "borrar {o}", "borra {o}", "eliminar {o}", "elimina {o}", "delete {o}", "remove {o} permanently",
        "pagar {o}", "paga {o}", "pay {o}", "transferir el saldo de {o}", "transfiere el monto de {o}", "wire the amount of {o}",
        "enviar {o} por correo", "envía {o}", "send {o}", "mandar {o} a todos los contactos", "manda {o}",
        "modificar {o} en la base de datos", "modifica el registro de {o}", "update {o} in the database",
        "aprobar {o}", "aprueba {o}", "approve {o}", "firmar {o}", "firma {o}", "sign {o}",
        "publicar {o}", "publica {o}", "post {o} publicly", "cancelar {o} en el sistema", "cancel {o}",
        "comprar {o} con la tarjeta corporativa", "purchase {o}", "sobrescribir {o}", "overwrite {o}",
        "revocar el acceso a {o}", "cambiar la contraseña de {o}", "ejecutar un script sobre {o}", "run a shell command on {o}",
        "vaciar la papelera con {o}", "dar de baja {o}",
    ],
}

OBJECTS = [
    "el reporte de ventas", "la factura 4512", "el contrato de arrendamiento", "la tabla de inventario",
    "el resumen del cliente", "la orden de compra", "el expediente del empleado", "la nómina de octubre",
    "el ticket de soporte", "el estado de cuenta", "la cotización", "los pendientes de hoy", "el correo del proveedor",
    "la hoja de Excel", "el documento en Notas", "la presentación trimestral", "el registro del cliente 889",
    "the sales report", "the invoice", "the customer record", "the spreadsheet", "the vendor email",
]

FRAMES = [
    "{a}", "Por favor, {a}", "{a} en el ERP", "Necesito {a}", "Quiero {a}", "{a} cuanto antes",
    "Paso 2: {a}", "{a} y avísame", "Please {a}", "{a} now", "Ayúdame a {a}", "Hay que {a}",
    "Tarea: {a}", "{a} desde Safari", "Puedes {a}?", "Siguiente acción: {a}",
]


def generate_dataset() -> list[tuple[str, str, str]]:
    """Devuelve filas (descripción, etiqueta, marco)."""
    rng = random.Random(SEED)
    rows = []
    for label, actions in ACTIONS.items():
        for f_idx, frame in enumerate(FRAMES):
            for action in rng.sample(actions, k=min(len(actions), 22)):
                text = frame.format(a=action.format(o=rng.choice(OBJECTS)))
                text = text[0].upper() + text[1:]
                if rng.random() < 0.25:
                    text = text.lower()
                rows.append((text, label, f"marco-{f_idx}"))
    rng.shuffle(rows)
    return rows


def build_pipeline() -> Pipeline:
    features = FeatureUnion([
        ("palabras", TfidfVectorizer(analyzer="word", ngram_range=(1, 2), strip_accents="unicode", sublinear_tf=True)),
        ("caracteres", TfidfVectorizer(analyzer="char_wb", ngram_range=(3, 5), strip_accents="unicode", sublinear_tf=True, max_df=0.5)),
    ])
    return Pipeline([
        ("features", features),
        ("clf", LogisticRegression(max_iter=3000, C=10.0, class_weight="balanced", random_state=SEED)),
    ])


def main(out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    rows = generate_dataset()
    with open(out_dir / "risk_dataset.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["description", "label", "frame"])
        w.writerows(rows)

    texts = [r[0] for r in rows]
    labels = [r[1] for r in rows]
    groups = [r[2] for r in rows]
    # Partición por marco de frase: la prueba solo contiene marcos no vistos.
    splitter = GroupShuffleSplit(n_splits=1, test_size=0.25, random_state=SEED)
    train_idx, test_idx = next(splitter.split(texts, labels, groups))
    x_train = [texts[i] for i in train_idx]
    y_train = [labels[i] for i in train_idx]
    x_test = [texts[i] for i in test_idx]
    y_test = [labels[i] for i in test_idx]

    model = build_pipeline()
    model.fit(x_train, y_train)
    pred = model.predict(x_test)

    report = classification_report(y_test, pred, labels=LABELS, output_dict=True, zero_division=0)
    metrics = {
        "model_version": MODEL_VERSION,
        "trained_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "sklearn_version": sklearn.__version__,
        "n_total": len(rows),
        "n_train": len(x_train),
        "n_test": len(x_test),
        "split": "GroupShuffleSplit por marco de frase, 25% prueba",
        "accuracy": round(accuracy_score(y_test, pred), 4),
        "recall_alto": round(report["alto"]["recall"], 4),
        "precision_alto": round(report["alto"]["precision"], 4),
        "f1_macro": round(report["macro avg"]["f1-score"], 4),
        "labels": LABELS,
        "confusion_matrix": confusion_matrix(y_test, pred, labels=LABELS).tolist(),
    }

    # El artefacto final se entrena con todo el dataset.
    final = build_pipeline()
    final.fit(texts, labels)
    with open(out_dir / "model.pkl", "wb") as f:
        pickle.dump({"pipeline": final, "version": MODEL_VERSION, "labels": LABELS}, f)
    with open(out_dir / "metrics.json", "w", encoding="utf-8") as f:
        json.dump(metrics, f, indent=2, ensure_ascii=False)

    print(f"Modelo {MODEL_VERSION} entrenado con {len(rows)} ejemplos")
    print(f"accuracy={metrics['accuracy']} recall_alto={metrics['recall_alto']} f1_macro={metrics['f1_macro']}")
    print(classification_report(y_test, pred, labels=LABELS, zero_division=0))


if __name__ == "__main__":
    main(Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent)
