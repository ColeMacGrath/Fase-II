#!/usr/bin/env sh
# Despliegue de la Capa Nube en Google Cloud Run.
# Uso: PROJECT_ID=mi-proyecto REGION=us-central1 ./deploy/cloudrun/deploy.sh
# Requiere gcloud autenticado y Docker con buildx. Las llaves se crean antes en Secret Manager.
set -eu
: "${PROJECT_ID:?Define PROJECT_ID}"
REGION="${REGION:-us-central1}"
REPO="agente-os"
IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO/agente-os-cloud:${TAG:-1.0.0}"
SA="agente-os-run@$PROJECT_ID.iam.gserviceaccount.com"

gcloud config set project "$PROJECT_ID"
gcloud services enable run.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com

gcloud artifacts repositories describe "$REPO" --location "$REGION" >/dev/null 2>&1 || \
  gcloud artifacts repositories create "$REPO" --repository-format=docker --location "$REGION"
gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet

docker buildx build --platform linux/amd64 -t "$IMAGE" --push ./backend

gcloud run deploy agente-os-cloud \
  --image "$IMAGE" \
  --region "$REGION" \
  --service-account "$SA" \
  --port 8000 \
  --cpu 1 --memory 1Gi \
  --concurrency 20 --timeout 120 \
  --min-instances 0 --max-instances 3 \
  --set-env-vars CLAUDE_MODEL=claude-opus-5-5,CLAUDE_EFFORT=low \
  --set-secrets "ANTHROPIC_API_KEY=anthropic-api-key:latest,AGENT_TOKEN=agent-token:latest" \
  --allow-unauthenticated

URL=$(gcloud run services describe agente-os-cloud --region "$REGION" --format 'value(status.url)')
echo "Servicio desplegado en $URL"
curl -fsS "$URL/health" && echo
