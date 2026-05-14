#!/usr/bin/env bash
# Blue-Green deployment script.
# Usage: APP_IMAGE=<image:tag> bash scripts/deploy.sh
set -euo pipefail

COMPOSE="docker compose -f docker-compose.blue-green.yml"
UPSTREAM_CONF="nginx/conf.d/upstream.conf"
HEALTH_RETRIES=15
HEALTH_INTERVAL=6   # seconds between retries

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
die()  { log "ERROR: $*"; exit 1; }

# ── Determine active / target slots ─────────────────────────────────────────
active_slot() {
    if grep -q "app-blue" "$UPSTREAM_CONF" 2>/dev/null; then
        echo "blue"
    else
        echo "green"
    fi
}

target_slot() {
    [[ "$(active_slot)" == "blue" ]] && echo "green" || echo "blue"
}

# ── Health check a container directly (bypasses nginx) ─────────────────────
wait_healthy() {
    local slot=$1
    local attempt=0
    log "Waiting for app-${slot} to be healthy..."
    while (( attempt < HEALTH_RETRIES )); do
        if $COMPOSE exec -T "app-${slot}" \
               curl -fsSL http://localhost:8000/health &>/dev/null; then
            log "app-${slot} is healthy ✓"
            return 0
        fi
        (( attempt++ ))
        log "  attempt ${attempt}/${HEALTH_RETRIES} — retrying in ${HEALTH_INTERVAL}s"
        sleep "$HEALTH_INTERVAL"
    done
    die "app-${slot} did not become healthy after ${HEALTH_RETRIES} attempts"
}

# ── Switch nginx upstream and reload ────────────────────────────────────────
switch_traffic() {
    local slot=$1
    log "Switching nginx upstream → app-${slot}"
    printf 'server app-%s:8000;\n' "$slot" > "$UPSTREAM_CONF"
    $COMPOSE exec -T nginx nginx -s reload
    sleep 2  # let nginx finish reload
}

# ── Rollback: restore previous upstream and stop failed slot ────────────────
rollback() {
    local previous=$1 failed=$2
    log "ROLLBACK: restoring traffic to app-${previous}"
    switch_traffic "$previous"
    log "Stopping failed slot app-${failed}"
    $COMPOSE stop "app-${failed}" || true
    die "Deployment failed — rolled back to ${previous}"
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
    : "${APP_IMAGE:?APP_IMAGE environment variable is required}"

    ACTIVE=$(active_slot)
    TARGET=$(target_slot)
    log "Active slot : $ACTIVE"
    log "Target slot : $TARGET"
    log "Image       : $APP_IMAGE"

    # Pull new image (non-fatal: image may already be loaded locally)
    log "Pulling $APP_IMAGE..."
    APP_IMAGE="$APP_IMAGE" $COMPOSE pull "app-${TARGET}" 2>/dev/null \
        || log "  pull skipped — using locally available image"

    # Start target slot with new image
    log "Starting app-${TARGET}..."
    APP_IMAGE="$APP_IMAGE" $COMPOSE up -d --no-deps "app-${TARGET}"

    # Health check target slot before touching nginx
    wait_healthy "$TARGET" || rollback "$ACTIVE" "$TARGET"

    # Switch traffic
    switch_traffic "$TARGET"

    # Verify traffic through nginx
    log "Verifying traffic via nginx..."
    if ! curl -fsSL http://localhost/health &>/dev/null; then
        rollback "$ACTIVE" "$TARGET"
    fi
    log "Traffic verified through nginx ✓"

    # Gracefully stop the old slot
    log "Stopping old slot app-${ACTIVE}..."
    $COMPOSE stop "app-${ACTIVE}"

    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Deployment complete"
    log "  Active  : app-${TARGET} ($APP_IMAGE)"
    log "  Standby : app-${ACTIVE} (stopped)"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

main "$@"
