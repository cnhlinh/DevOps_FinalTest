# DevOps Pipeline — Final Test

A FastAPI application demonstrating a complete CI/CD pipeline with linting, testing, static analysis, Docker image publishing, and zero-downtime blue-green deployment.

---

## Pipeline Overview

```
push / PR
    │
    ▼
┌─────────┐     ┌──────────┐     ┌────────────┐     ┌───────────┐     ┌──────────────┐
│  Lint   │────▶│   Test   │────▶│ SonarQube  │────▶│   Build   │────▶│    Deploy    │
│ (ruff)  │     │ (pytest) │     │ Quality    │     │  & Push   │     │ Blue-Green   │
│         │     │ matrix   │     │   Gate     │     │  (GHCR)   │     │ (main only)  │
└─────────┘     └──────────┘     └────────────┘     └───────────┘     └──────────────┘
```

Each stage must pass before the next one starts. A failed Quality Gate blocks the Docker build and deploy.

---

## Pipeline Stages

### 1. Lint — `ruff`

Runs on every push and pull request.

- `ruff check` — enforces pycodestyle, pyflakes, isort, naming, and bugbear rules
- `ruff format --check` — enforces consistent formatting
- Targets `app/` and `tests/`

### 2. Test — pytest (matrix)

Runs after lint passes.

| Matrix axis | Values |
|---|---|
| Python version | 3.11, 3.12 |
| OS | ubuntu-latest |

- Runs the full test suite with `--cov=app`
- Produces `coverage.xml` and `test-results.xml`
- Coverage and JUnit artifacts are uploaded from the `python 3.12 / ubuntu-latest` cell for consumption by SonarQube

### 3. SonarQube — Scan & Quality Gate

Runs after all test matrix cells pass.

- Downloads the `coverage.xml` artifact
- Runs `sonarqube-scan-action` with `sonar.qualitygate.wait=true` — the step blocks until the gate result is available
- A second `sonarqube-quality-gate-action` step surfaces a clear FAILED status if the gate fails
- **Failure here prevents the Docker build and deploy from running**

Configuration lives in [sonar-project.properties](sonar-project.properties).

### 4. Build & Push — Docker (GHCR)

Runs after the Quality Gate passes.

- Multi-stage Dockerfile: `builder` installs dependencies, `production` copies only the installed packages and app source, runs as a non-root user
- Uses Docker Buildx with GitHub Actions cache (`type=gha`)
- Pushes to `ghcr.io/<owner>/<repo>` with the following tags:

| Tag | When |
|---|---|
| `sha-<short-sha>` | always |
| `<branch-name>` | always |
| `latest` | push to `main` only |
| `<semver>` | on version tags |

- Generates SBOM and provenance attestations
- Image is **not** pushed on pull requests (only built locally)

### 5. Deploy — Blue-Green

Runs only on `push` to `main`, after the Docker build succeeds. Targets a `self-hosted` runner labeled `local`.

**How it works:**

```
nginx (port 80)
    │
    ├── app-blue  :8000  ← active
    └── app-green :8000  ← standby
```

1. Build the new image into the local Docker daemon
2. Start the stack (`docker compose -f docker-compose.blue-green.yml up -d`)
3. Smoke-test the currently active slot through nginx
4. Run `scripts/deploy.sh`:
   - Detect active slot (blue or green) by reading `nginx/conf.d/upstream.conf`
   - Start the **target** slot with the new image
   - Health-check the target slot directly (up to 15 retries × 6 s)
   - Switch nginx upstream to the target slot and reload
   - Verify traffic flows through nginx
   - Stop the old slot
   - **Automatic rollback**: if health checks or the nginx verify fail, the script restores the previous upstream and stops the failed slot
5. Smoke-test the newly active slot through nginx

---

## Application

- **Framework**: FastAPI + Uvicorn
- **Python**: 3.12 (production), 3.11–3.12 (tested)
- **Endpoints**:
  - `GET /` — root info
  - `GET /health` — health check (used by Docker HEALTHCHECK and deploy smoke tests)
  - `GET /items`, `POST /items` — example CRUD routes

---

## Local Development

```bash
# Install dependencies
pip install -e ".[dev]"

# Lint
ruff check app/ tests/
ruff format app/ tests/

# Test
pytest tests/ --cov=app

# Run locally
uvicorn app.main:app --reload

# Run with Docker Compose
docker compose up
```

---

## Required Secrets

| Secret | Purpose |
|---|---|
| `SONAR_TOKEN` | SonarQube authentication |
| `SONAR_HOST_URL` | SonarQube server URL |
| `GITHUB_TOKEN` | Automatically provided — used to push to GHCR |
