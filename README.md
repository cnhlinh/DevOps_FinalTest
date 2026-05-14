# LinhCNH — DevOps Pipeline Final Test

A FastAPI application with a complete CI/CD pipeline: lint → test → SonarQube quality gate → Docker build → zero-downtime blue-green deployment.

---

## Pipeline

```
push to main / PR
        │
        ▼
  ┌───────────┐   ┌───────────┐   ┌─────────────┐   ┌───────────┐   ┌────────────┐
  │   Lint    │──▶│   Test    │──▶│  SonarQube  │──▶│   Build   │──▶│   Deploy   │
  │  (ruff)   │   │ (pytest)  │   │Quality Gate │   │ push GHCR │   │ Blue-Green │
  │cloud runner│   │py3.11,3.12│   │ cloud runner│   │cloud runner│   │self-hosted │
  └───────────┘   └───────────┘   └─────────────┘   └───────────┘   └────────────┘
```

- Jobs 1–4 run on **GitHub-hosted** `ubuntu-latest` runners.
- Job 5 (Deploy) runs on the **self-hosted** runner on your local machine.
- A failed Quality Gate blocks Build and Deploy.

---

## Prerequisites

| Tool | Purpose |
|---|---|
| Python 3.11+ | Local development |
| Docker Desktop | Containers + blue-green stack |
| ngrok | Expose local SonarQube to GitHub Actions |
| GitHub account | CI/CD + GHCR |

---

## Setup

### 1. Clone and install

```bash
git clone https://github.com/<you>/LinhCNH_FinalTest_DevOps.git
cd LinhCNH_FinalTest_DevOps
pip install -e ".[dev]"
```

### 2. Start local SonarQube

```bash
docker compose up -d sonarqube
```

Wait ~60 s then open **http://localhost:9000** and log in with `admin / admin`.
Change the password when prompted, then create a project:

1. **Projects → Create project → Manually**
2. Project key: `linhcnh-finaltest-devops`
3. **Locally → Generate token** → copy the token

### 3. Expose SonarQube with ngrok

GitHub Actions cloud runners cannot reach `localhost:9000` on your machine.
ngrok creates a public HTTPS tunnel to it.

```bash
# Install (macOS)
brew install ngrok

# Authenticate (one-time, free account at ngrok.com)
ngrok config add-authtoken <your-ngrok-token>

# Start tunnel
ngrok http 9000
```

Copy the forwarding URL, e.g. `https://a1b2-203-0-113-42.ngrok-free.app`.

> **Keep the ngrok terminal open** 

### 4. Add GitHub repository secrets

Go to **repo → Settings → Secrets and variables → Actions → New repository secret**.

| Secret | Value |
|---|---|
| `SONAR_TOKEN` | Token generated in step 2 |
| `SONAR_HOST_URL` | ngrok URL from step 3, e.g. `https://a1b2-….ngrok-free.app` |

`GITHUB_TOKEN` is provided automatically by GitHub Actions — no action needed.

### 5. Register the self-hosted runner

The deploy job runs on your machine. GitHub needs a runner agent installed here.

**Get a runner token:**
Go to **repo → Settings → Actions → Runners → New self-hosted runner** and copy the token from the `--token` line.

**Install the runner:**
```bash
bash scripts/setup-runner.sh \
  https://github.com/<you>/LinhCNH_FinalTest_DevOps \
  <runner-token>
```

The script downloads the runner binary, registers it with labels `self-hosted, macOS, ARM64`, and installs it as a launchd background service so it survives reboots.

**Verify it is online:**
Go to **repo → Settings → Actions → Runners** — your machine should appear as **Idle**.

---

## How the Deploy works

```
nginx :80
  │
  ├── app-blue  :8000  ← initially active
  └── app-green :8000  ← standby
```

`scripts/deploy.sh`:
1. Reads `nginx/conf.d/upstream.conf` to find the active slot (blue).
2. Starts the **target** slot (green) with the new image.
3. Health-checks green directly (15 retries × 6 s) — **rollback fires here if unhealthy**.
4. Rewrites `upstream.conf` to `server app-green:8000;` and runs `nginx -s reload`.
5. Verifies traffic flows through nginx — **rollback fires here if broken**.
6. Stops the old (blue) slot.
7. App stays running on `http://localhost` after the job finishes.

---

## Local Development

```bash
# Lint
ruff check app/ tests/
ruff format --check app/ tests/

# Test
pytest tests/ --cov=app --cov-report=term-missing

# Run locally
uvicorn app.main:app --reload

# Build Docker image
docker build -t devops-api:local .
```

**Blue-green without CI:**
```bash
# Start stack + switch blue → green
echo "server app-blue:8000;" > nginx/conf.d/upstream.conf
APP_IMAGE=devops-api:local docker compose -f docker-compose.blue-green.yml up -d --wait
APP_IMAGE=devops-api:local bash scripts/deploy.sh

# Check status
docker compose -f docker-compose.blue-green.yml ps -a
cat nginx/conf.d/upstream.conf

# Stop everything
docker compose -f docker-compose.blue-green.yml down --volumes --remove-orphans
```

**Runner management:**
```bash
cd ~/actions-runner
./svc.sh status
./svc.sh stop
./svc.sh start
```

---

## Project Structure

```
├── app/
│   ├── main.py              # FastAPI app
│   ├── models.py            # Pydantic models
│   └── routes/
│       └── health.py        # GET /health
├── tests/
│   ├── conftest.py
│   └── test_health.py
├── nginx/
│   ├── nginx.conf
│   └── conf.d/upstream.conf # rewritten by deploy.sh on each slot switch
├── scripts/
│   ├── deploy.sh            # blue-green switch + rollback
│   └── setup-runner.sh      # self-hosted runner installer
├── .github/workflows/
│   └── ci-cd.yml            # full pipeline
├── Dockerfile               # multi-stage, non-root user
├── docker-compose.yml       # app + local SonarQube
├── docker-compose.blue-green.yml
├── sonar-project.properties
└── pyproject.toml
```

---

## API Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/health` | Health check — used by Docker HEALTHCHECK and deploy smoke tests |
