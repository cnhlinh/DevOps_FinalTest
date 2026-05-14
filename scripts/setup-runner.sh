#!/usr/bin/env bash
# Install and register a GitHub Actions self-hosted runner on this machine.
#
# Usage:
#   bash scripts/setup-runner.sh <repo-url> <runner-token>
#
# Where to get the runner token:
#   GitHub → your repo → Settings → Actions → Runners → "New self-hosted runner"
#   Copy the token from the --token line in the "Configure" block.
#   (Token expires after 1 hour — use it immediately.)
#
# Example:
#   bash scripts/setup-runner.sh https://github.com/you/repo AABBCCDD...
set -euo pipefail

REPO_URL="${1:?Usage: setup-runner.sh <https://github.com/owner/repo> <runner-token>}"
RUNNER_TOKEN="${2:?Usage: setup-runner.sh <https://github.com/owner/repo> <runner-token>}"
RUNNER_VERSION="2.321.0"
RUNNER_DIR="${HOME}/actions-runner"
RUNNER_NAME="${RUNNER_NAME:-$(hostname)-local}"
RUNNER_LABELS="self-hosted,local"

log() { echo "[setup-runner] $*"; }

# ── Detect OS / arch ──────────────────────────────────────────────────────────
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)       ARCH="x64"   ;;
  arm64|aarch64) ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

log "Platform : ${OS}-${ARCH}"
log "Runner   : ${RUNNER_NAME}"
log "Labels   : ${RUNNER_LABELS}"
log "Dir      : ${RUNNER_DIR}"

# ── Download runner package ───────────────────────────────────────────────────
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

TARBALL="actions-runner-${OS}-${ARCH}-${RUNNER_VERSION}.tar.gz"
URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${TARBALL}"

if [[ ! -f "$TARBALL" ]]; then
  log "Downloading ${TARBALL}..."
  curl -fsSL -o "$TARBALL" "$URL"
else
  log "Found cached ${TARBALL}, skipping download."
fi

log "Extracting..."
tar xzf "$TARBALL"

# ── Configure runner ──────────────────────────────────────────────────────────
log "Configuring runner against ${REPO_URL}..."
./config.sh \
  --url     "$REPO_URL" \
  --token   "$RUNNER_TOKEN" \
  --name    "$RUNNER_NAME" \
  --labels  "$RUNNER_LABELS" \
  --work    "_work" \
  --unattended \
  --replace          # replace any existing registration with this name

# ── Install as a background service ──────────────────────────────────────────
log "Installing runner as a system service..."

if [[ "$OS" == "darwin" ]]; then
  # macOS — launchd service (no sudo needed for user-level service)
  ./svc.sh install
  ./svc.sh start
  log ""
  log "Runner service installed (launchd). Management commands:"
  log "  cd ${RUNNER_DIR} && ./svc.sh status"
  log "  cd ${RUNNER_DIR} && ./svc.sh stop"
  log "  cd ${RUNNER_DIR} && ./svc.sh start"
else
  # Linux — systemd service (requires sudo)
  sudo ./svc.sh install
  sudo ./svc.sh start
  log ""
  log "Runner service installed (systemd). Management commands:"
  log "  sudo systemctl status actions.runner.*.service"
  log "  sudo systemctl stop   actions.runner.*.service"
  log "  sudo systemctl start  actions.runner.*.service"
fi

log ""
log "Done! The runner '${RUNNER_NAME}' is now online."
log "Verify at: ${REPO_URL}/settings/actions/runners"
