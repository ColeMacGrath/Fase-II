# syntax=docker/dockerfile:1

# Etapa 1: dependencias y entrenamiento del clasificador.
FROM python:3.13-slim AS builder
WORKDIR /build
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY model/train_risk_model.py model/
RUN python model/train_risk_model.py /build/model

# Etapa 2: imagen final mínima.
FROM python:3.13-slim
LABEL org.opencontainers.image.title="agente-os-cloud" \
      org.opencontainers.image.version="1.0.0"
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    MODEL_DIR=/app/model \
    PORT=8000
RUN useradd --create-home --uid 10001 agente
WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /build/model/ ./model/
COPY app ./app
COPY tests ./tests
COPY scripts ./scripts
USER agente
EXPOSE 8000
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s \
  --retries=3 CMD python scripts/healthcheck.py
CMD ["sh", "-c", \
     "uvicorn app.main:app --host 0.0.0.0 --port ${PORT}"]
