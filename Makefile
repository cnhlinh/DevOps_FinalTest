IMAGE      ?= devops-api:local
COMPOSE_BG  = docker compose -f docker-compose.blue-green.yml
COMPOSE_DEV = docker compose

# ── Local pipeline (mirrors CI stages) ────────────────────────────────────────

.PHONY: lint
lint:                         ## ruff lint + format check
	ruff check app/ tests/ --output-format=text
	ruff format --check app/ tests/

.PHONY: lint-fix
lint-fix:                     ## auto-fix all ruff issues
	ruff check app/ tests/ --fix
	ruff format app/ tests/

.PHONY: test
test:                         ## pytest with coverage
	pytest tests/ --cov=app --cov-report=term-missing --cov-report=xml:coverage.xml -v

.PHONY: build
build:                        ## build Docker image locally
	docker build --tag $(IMAGE) .

# ── Blue-Green deploy (fully local, no server needed) ─────────────────────────

.PHONY: bg-up
bg-up: build                  ## start both slots + nginx
	echo "server app-blue:8000;" > nginx/conf.d/upstream.conf
	APP_IMAGE=$(IMAGE) $(COMPOSE_BG) up -d --wait

.PHONY: bg-deploy
bg-deploy: bg-up              ## run the blue→green switch
	APP_IMAGE=$(IMAGE) bash scripts/deploy.sh

.PHONY: bg-status
bg-status:                    ## show running containers + active upstream
	$(COMPOSE_BG) ps -a
	@echo "\nActive upstream:"; cat nginx/conf.d/upstream.conf

.PHONY: bg-down
bg-down:                      ## stop and remove everything
	$(COMPOSE_BG) down --volumes --remove-orphans

# ── Full local pipeline (no act needed) ───────────────────────────────────────

.PHONY: pipeline
pipeline: lint test build bg-deploy   ## lint → test → build → blue-green deploy
	@echo "\n=== Health check via nginx ==="
	curl -fsSL http://localhost/health | python3 -m json.tool
	@echo "\n=== Pipeline complete ==="

# ── SonarQube (local Docker) ───────────────────────────────────────────────────

.PHONY: sonar-up
sonar-up:                     ## start local SonarQube (first run takes ~60s)
	$(COMPOSE_DEV) up -d sonarqube
	@echo "SonarQube → http://localhost:9000  (admin / admin)"

.PHONY: sonar-scan
sonar-scan: test              ## run sonar-scanner against local SonarQube
	docker run --rm --network host \
	  -v "$$(pwd):/usr/src" \
	  sonarsource/sonar-scanner-cli \
	  -Dsonar.host.url=http://localhost:9000 \
	  -Dsonar.token=$${SONAR_TOKEN:-admin}

# ── Run the full CI workflow locally with act ──────────────────────────────────

.PHONY: act-pipeline
act-pipeline:                 ## run entire workflow with act (needs: brew install act)
	act push \
	  -W .github/workflows/ci-cd.yml \
	  --var GITHUB_REF=refs/heads/main \
	  --secret SONAR_TOKEN=$${SONAR_TOKEN:-} \
	  --secret SONAR_HOST_URL=$${SONAR_HOST_URL:-http://host.docker.internal:9000}

# ── Self-hosted runner management ─────────────────────────────────────────────
# REPO  = https://github.com/your-org/your-repo
# TOKEN = one-time token from repo Settings → Actions → Runners → New runner

.PHONY: runner-install
runner-install:               ## install + register self-hosted runner (REPO= TOKEN= required)
	@test -n "$(REPO)"  || (echo "Usage: make runner-install REPO=https://github.com/owner/repo TOKEN=xxx"; exit 1)
	@test -n "$(TOKEN)" || (echo "Usage: make runner-install REPO=https://github.com/owner/repo TOKEN=xxx"; exit 1)
	bash scripts/setup-runner.sh "$(REPO)" "$(TOKEN)"

.PHONY: runner-status
runner-status:                ## show runner service status
	@cd ~/actions-runner && ./svc.sh status 2>/dev/null || echo "Runner not installed as a service. Is ~/actions-runner present?"

.PHONY: runner-stop
runner-stop:                  ## stop runner service
	cd ~/actions-runner && ./svc.sh stop

.PHONY: runner-start
runner-start:                 ## start runner service
	cd ~/actions-runner && ./svc.sh start

.PHONY: runner-uninstall
runner-uninstall:             ## unregister + remove runner service
	cd ~/actions-runner && ./svc.sh stop && ./svc.sh uninstall && ./config.sh remove --token "$(TOKEN)"

.PHONY: help
help:                         ## show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*##"}{printf "  %-18s %s\n",$$1,$$2}'
