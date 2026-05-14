# ── Stage 1: dependency builder ──────────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /build

# gcc needed by some C-extension wheels
RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc \
    && rm -rf /var/lib/apt/lists/*

COPY pyproject.toml .
# Install only production deps into an isolated prefix so we can COPY them cleanly
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir --prefix=/install ".[dev]" --no-deps \
    && pip install --no-cache-dir --prefix=/install .

# ── Stage 2: production image ─────────────────────────────────────────────────
FROM python:3.12-slim AS production

# Security: non-root user
RUN groupadd -r appuser \
    && useradd -r -g appuser -d /app -s /sbin/nologin -c "App user" appuser

# curl for HEALTHCHECK
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy installed packages from builder stage
COPY --from=builder /install /usr/local

# Copy application source (owned by non-root)
COPY --chown=appuser:appuser app/ ./app/

ARG APP_VERSION=0.1.0
ENV APP_VERSION=${APP_VERSION} \
    ENVIRONMENT=production \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD curl -fsSL http://localhost:8000/health || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
