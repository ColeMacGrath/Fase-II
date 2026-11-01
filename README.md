# Agente OS · Fase II

## De Fase I a Fase II

En Fase I se construyó el caso de negocio de un agente que automatiza tareas de pantalla con dos capas: una **Capa Local**, que procesa la pantalla en el equipo y resuelve la mayoría de las tareas sin que los datos salgan de él, y una **Capa Nube Privada**, efímera, que solo hace el razonamiento complejo. El caso definió controles de privacidad y gobernanza con KPIs medibles para la compuerta del mes 5.

Esta fase entrega el MVP de esa plataforma: un flujo completo que recorre las dos capas, con cada control implementado y validado contra su KPI.

| Concepto de Fase I | Implementación en Fase II | KPI validado |
|---|---|---|
| Capa Local en el dispositivo | App SwiftUI con captura de pantalla, OCR en el dispositivo y router local | Tareas resueltas en local frente a nube |
| Filtro Ciego, riesgo R04 | Enmascarado de tarjeta con Luhn, CLABE, RFC, CURP, correo y teléfono en texto e imagen | 100% de cargas enmascaradas, 0 datos personales en el servidor |
| Capa Nube Privada efímera | Contenedor FastAPI sin estado, de solo lectura, sin volúmenes | Sin persistencia en disco |
| Validador contra inyección, riesgo R01 | Detector determinista que cancela la ejecución antes de llamar al modelo | Detección de 98% o más en red teaming |
| Semáforo de riesgo de 3 niveles | Clasificador entrenado `model.pkl` combinado con reglas que nunca bajan un riesgo | Recall de 100% en riesgo alto |
| Confirmación biométrica | Touch ID antes de cualquier acción de riesgo alto | 0 acciones críticas sin confirmación |
| Libro Mayor Criptográfico, riesgo R03 | Bitácora local con hashes SHA-256 encadenados y verificación de integridad | 100% de acciones con traza verificable |

## Estructura del repositorio

```
.
├── Fase II.xcodeproj         Proyecto de Xcode de la app de macOS
├── Fase II/                  Código de la app SwiftUI: frontend y Capa Local
│   ├── Local/                Captura, OCR, Filtro Ciego, router, Touch ID, Libro Mayor, ejecutor
│   ├── Network/              Cliente REST de la Capa Nube
│   ├── Models/               Contratos de la API, estado de la app y escenarios de demo
│   ├── Views/                Interfaz
│   └── Demo/                 Pantallas de ejemplo para los escenarios
├── backend/                  Capa Nube: backend
│   ├── app/                  API FastAPI, guardrails, clasificador y planificador
│   ├── model/                Script de entrenamiento del clasificador de riesgo
│   ├── tests/                Suite pytest y sets de validación
│   ├── scripts/              Prueba de humo, chequeo de salud, simulación y evaluación
│   ├── Dockerfile            Imagen multi-etapa
│   ├── requirements.txt      Dependencias con versión fija
│   └── .env.example          Variables de entorno
├── docker-compose.yml        Ejecución local del contenedor
├── deploy/cloudrun/          Manifiesto y script de despliegue en Google Cloud Run
└── .github/workflows/        Integración continua: build, pruebas y prueba de humo
```

El manual de despliegue en la nube y el documento de validación y pruebas se entregan en PDF por separado.

## Requisitos

| Componente | Versión usada |
|---|---|
| macOS | 27.2, Apple silicon |
| Xcode | 27.2 |
| Docker Engine | 29.5 con Docker Compose 5.6, o Docker Desktop |
| Python en el contenedor | 3.13 |

En macOS sin Docker Desktop se puede usar Colima:

```bash
brew install colima docker docker-compose docker-buildx
colima start --cpu 4 --memory 6
```

## Ejecución local del backend

```bash
# 1. Variables de entorno
cp backend/.env.example backend/.env
# Edita backend/.env y coloca tu ANTHROPIC_API_KEY. Sin llave, el backend arranca con el planificador determinista.

# 2. Construir la imagen y levantar el contenedor
docker compose up -d --build

# 3. Verificar
curl http://localhost:8000/health
./backend/scripts/smoke_test.sh

# 4. Pruebas dentro del contenedor
docker compose run --rm backend pytest -v

# 5. Simulación y evaluación del modelo
docker exec agente-os-cloud python scripts/simular.py
docker exec agente-os-cloud python scripts/evaluar_modelo.py
```

La documentación interactiva de la API queda en `http://localhost:8000/docs`.

El build entrena el clasificador de riesgo dentro de la imagen con semilla fija. Así `model.pkl` siempre corresponde a la versión de scikit-learn instalada y el resultado es reproducible.

## Ejecución de la app de macOS

1. Abre `Fase II.xcodeproj` en Xcode.
2. En *Signing & Capabilities* elige tu equipo de desarrollo.
3. Ejecuta con ⌘R. La app se conecta a `http://localhost:8000`; la URL se cambia en *Sistema y KPIs*.
4. La primera captura de pantalla pide el permiso de Grabación de pantalla.

El menú **Demo** carga escenarios con pantallas de ejemplo: abrir un sitio en local, resumir un correo con datos personales, extraer una tabla a CSV, pagar una factura y una página con una instrucción oculta.

## API

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/health` | Estado del servicio, modo del planificador y métricas del clasificador |
| POST | `/v1/analyze` | Recibe la tarea, el texto de pantalla enmascarado y la captura opcional; devuelve el plan con nivel de riesgo |
| POST | `/v1/risk` | Clasifica una acción con el modelo y las reglas |
| POST | `/v1/guard` | Detecta inyección y datos personales en un texto |

Ejemplo:

```bash
curl -X POST http://localhost:8000/v1/analyze \
  -H 'Content-Type: application/json' \
  -d '{"task":"Resume el correo","screen_text":"Factura F-4512 por $91,060.00"}'
```

Si `AGENT_TOKEN` está definido, cada solicitud debe incluir el encabezado `X-Agent-Token`.

## Modos del planificador

El backend tiene dos implementaciones del planificador con la misma interfaz:

- **Claude**: se activa cuando existe `ANTHROPIC_API_KEY`. Usa `claude-opus-5-5` con salida estructurada en JSON Schema y fallback del servidor.
- **Determinista**: se activa sin llave o con `CLAUDE_MOCK=1`. Genera planes reproducibles con reglas y es el que usa la suite de pruebas para que los resultados no dependan de la red ni tengan costo.

Las barreras de seguridad, el clasificador de riesgo, la validación de entrada y el contrato de la API son los mismos en ambos modos.

## Resultados de validación

| Prueba | Resultado |
|---|---|
| Suite pytest dentro del contenedor | 57 de 57 |
| Clasificador solo, 60 frases escritas a mano | Exactitud 88.3%, recall en alto 95% |
| Clasificador con reglas | Exactitud 88.3%, recall en alto 100%, ningún error baja el riesgo |
| Inyección, set de red teaming | 45 de 45 detectados, 0 falsos positivos en 39 benignos |
| Inyección, set independiente | 14 de 15 detectados, 0 falsos positivos en 15 benignos |
| Datos personales llegados al servidor desde la app | 0 |

## Despliegue en la nube

La estrategia es un contenedor en un PaaS: Google Cloud Run, con Artifact Registry para la imagen y Secret Manager para las credenciales. Requiere un proyecto de Google Cloud con facturación activa, Google Cloud CLI autenticado y Docker con buildx.

```bash
# 1. Proyecto y servicios
gcloud config set project PROJECT_ID
gcloud services enable run.googleapis.com \
  artifactregistry.googleapis.com secretmanager.googleapis.com

# 2. Credenciales en Secret Manager
printf "%s" "$ANTHROPIC_API_KEY" | \
  gcloud secrets create anthropic-api-key --data-file=-
openssl rand -hex 32 | \
  gcloud secrets create agent-token --data-file=-

# 3. Cuenta de servicio con acceso solo a sus secretos
gcloud iam service-accounts create agente-os-run
for s in anthropic-api-key agent-token; do
  gcloud secrets add-iam-policy-binding $s \
    --member=serviceAccount:agente-os-run@PROJECT_ID.iam.gserviceaccount.com \
    --role=roles/secretmanager.secretAccessor
done

# 4. Repositorio de imágenes, build para linux/amd64 y despliegue
PROJECT_ID=PROJECT_ID REGION=us-central1 ./deploy/cloudrun/deploy.sh
```

El script `deploy/cloudrun/deploy.sh` crea el repositorio en Artifact Registry, construye y publica la imagen, despliega el servicio y verifica `/health`. Como alternativa declarativa, `deploy/cloudrun/service.yaml` define el mismo servicio con sondas de arranque y de vida:

```bash
gcloud run services replace deploy/cloudrun/service.yaml --region us-central1
```

Para revertir a una versión anterior:

```bash
gcloud run services update-traffic agente-os-cloud \
  --to-revisions=REVISION=100 --region us-central1
```

Al final, en la app se cambia la URL del backend en *Sistema y KPIs* por la URL del servicio y se captura el token de agente.

## Seguridad de credenciales

- La llave de la API solo vive en `backend/.env`, que está en `.gitignore` y `.dockerignore`.
- En la nube la llave se inyecta desde Secret Manager; nunca se escribe en la imagen.
- El repositorio incluye únicamente `backend/.env.example` con valores vacíos.
