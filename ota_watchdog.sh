#!/bin/bash
# ota_watchdog.sh
# Runs right after ota_check.sh flips to a new slot. Watches the app for
# GRACE_SECONDS; if it crashes or fails the health check, rolls back.

set -euo pipefail

APP_ROOT="/opt/app"
STATE_FILE="$APP_ROOT/state.json"
APP_SERVICE="app.service"
HEALTH_CHECK="$APP_ROOT/ota/health_check.sh"
GRACE_SECONDS=30
POLL_INTERVAL=3

log() { logger -t ota-watchdog "$1" 2>/dev/null; echo "[ota-watchdog] $1"; }

state_get() { jq -r ".$1 // empty" "$STATE_FILE"; }
state_set() {
    local tmp
    tmp=$(mktemp)
    jq "$1" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

status=$(state_get status)
if [ "$status" != "testing" ]; then
    log "No pending deployment to verify (status=$status), exiting"
    exit 0
fi

log "Watching new deployment for ${GRACE_SECONDS}s"
elapsed=0
healthy=true

while [ "$elapsed" -lt "$GRACE_SECONDS" ]; do
    if ! systemctl is-active --quiet "$APP_SERVICE"; then
        log "Service is not active during grace period"
        healthy=false
        break
    fi

    if [ -x "$HEALTH_CHECK" ]; then
        if ! "$HEALTH_CHECK"; then
            log "Health check failed"
            healthy=false
            break
        fi
    fi

    sleep "$POLL_INTERVAL"
    elapsed=$((elapsed + POLL_INTERVAL))
done

if [ "$healthy" == "true" ] && systemctl is-active --quiet "$APP_SERVICE"; then
    log "New version confirmed healthy"
    state_set '.status = "stable"'
    exit 0
fi

log "New version unhealthy, rolling back"
"$APP_ROOT/ota/ota_rollback.sh"
