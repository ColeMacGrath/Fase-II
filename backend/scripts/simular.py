"""Simulación local del modelo, siguiendo los pasos del Tema 15.

Carga model.pkl, clasifica casos comunes y extremos y muestra las
probabilidades por clase.

Uso: python scripts/simular.py
"""

import os
import pickle
import sys
from pathlib import Path

MODEL_DIR = Path(os.getenv("MODEL_DIR", Path(__file__).resolve().parent.parent / "model"))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

with open(MODEL_DIR / "model.pkl", "rb") as f:
    artifact = pickle.load(f)
model = artifact["pipeline"]
print(f"Modelo cargado: {artifact['version']}\n")

casos_comunes = [
    "Abrir Safari en el portal de proveedores",
    "Guardar el resumen como notas.txt",
    "Pagar la factura 4512 al proveedor",
    "Copiar el número de pedido",
    "Enviar el contrato al cliente",
]
casos_extremos = [
    "",                                   # texto vacío
    "a",                                  # una sola letra
    "Revisa el saldo sin modificar nada",  # palabra sensible en contexto benigno
    "borrador del correo",                 # parecido a 'borrar'
    "DELETE EVERYTHING NOW!!!",            # mayúsculas y signos
    "🚀🚀🚀",                              # solo emojis
]

for titulo, casos in [("Casos comunes", casos_comunes), ("Casos extremos", casos_extremos)]:
    print(f"== {titulo} ==")
    for i, texto in enumerate(casos, 1):
        pred = model.predict([texto])[0]
        proba = ", ".join(f"{c} {p:.3f}" for c, p in zip(model.classes_, model.predict_proba([texto])[0]))
        print(f"{i}. {texto!r} -> {pred}   ({proba})")
    print()
