#!/bin/bash
# ota_rollback.sh
# Flips "current" back to the previous slot/version recorded in state.json
# and restarts the app. Called by the watchdog on a failed deployment, but
# safe to run manually too.

set -euo pipefail

APP_ROOT="/opt/app"
STATE_FILE="$APP_ROOT/state.json"
CURRENT_LINK="$APP_ROOT/current"
APP_SERVICE="app.service"
SLOT_A="$APP_ROOT/slot_a"
SLOT_B="$APP_ROOT/slot_b"

log() { logger -t ota-rollback "$1" 2>/dev/null; echo "[ota-rollback] $1"; }

state_get() { jq -r ".$1 // empty" "$STATE_FILE"; }
state_set() {
    local tmp
    tmp=$(mktemp)
    jq "$1" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

prev_slot=$(state_get previous_slot)
prev_version=$(state_get previous_version)

if [ -z "$prev_slot" ] || [ "$prev_slot" == "none" ]; then
    log "No previous slot recorded, cannot roll back automatically"
    state_set '.status = "failed"'
    exit 1
fi

if [ "$prev_slot" == "slot_a" ]; then
    target="$SLOT_A"
else
    target="$SLOT_B"
fi

log "Rolling back to $prev_slot ($prev_version)"
ln -sfn "$target" "$CURRENT_LINK.tmp"
mv -Tf "$CURRENT_LINK.tmp" "$CURRENT_LINK"

state_set ".current_slot = \"$prev_slot\" | .current_version = \"$prev_version\" | .status = \"rolled_back\""

systemctl restart "$APP_SERVICE"
log "Rollback complete, running $prev_slot at $prev_version"
