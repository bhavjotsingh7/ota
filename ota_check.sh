#!/bin/bash
# ota_check.sh
# Checks the GitHub repo for a new commit, deploys it into the inactive
# A/B slot, flips the "current" symlink, restarts the app, and hands off
# to the watchdog to confirm health (or roll back).
#
# Intended to be run periodically by ota-check.timer via systemd.

set -euo pipefail

# ===== Config — edit these =====
REPO_URL="git@github.com:YOUR_USERNAME/YOUR_REPO.git"   # use SSH deploy key auth
BRANCH="main"
APP_SERVICE="app.service"

# ===== Fixed paths =====
APP_ROOT="/opt/app"
SLOT_A="$APP_ROOT/slot_a"
SLOT_B="$APP_ROOT/slot_b"
CURRENT_LINK="$APP_ROOT/current"
STATE_FILE="$APP_ROOT/state.json"

log() { logger -t ota-check "$1" 2>/dev/null; echo "[ota-check] $1"; }

now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

state_get() { jq -r ".$1 // empty" "$STATE_FILE" 2>/dev/null; }

state_set() {
    local tmp
    tmp=$(mktemp)
    jq "$1" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

init_state_if_missing() {
    if [ ! -f "$STATE_FILE" ]; then
        cat > "$STATE_FILE" <<EOF
{
  "current_slot": "none",
  "current_version": "",
  "previous_slot": "none",
  "previous_version": "",
  "status": "uninitialized",
  "last_check": ""
}
EOF
    fi
}

get_current_slot_name() {
    local target
    target=$(readlink -f "$CURRENT_LINK" 2>/dev/null || echo "")
    if [[ "$target" == "$SLOT_A" ]]; then
        echo "slot_a"
    elif [[ "$target" == "$SLOT_B" ]]; then
        echo "slot_b"
    else
        echo "none"
    fi
}

slot_path() { [[ "$1" == "slot_a" ]] && echo "$SLOT_A" || echo "$SLOT_B"; }
other_slot() { [[ "$1" == "slot_a" ]] && echo "slot_b" || echo "slot_a"; }

bootstrap() {
    mkdir -p "$APP_ROOT"
    init_state_if_missing
    if [ ! -d "$SLOT_A/.git" ]; then
        log "First run: cloning into slot_a"
        git clone --branch "$BRANCH" "$REPO_URL" "$SLOT_A"
    fi
    if [ ! -e "$CURRENT_LINK" ]; then
        ln -sfn "$SLOT_A" "$CURRENT_LINK"
        local ver
        ver=$(git -C "$SLOT_A" rev-parse HEAD)
        state_set ".current_slot = \"slot_a\" | .current_version = \"$ver\" | .status = \"stable\" | .last_check = \"$(now)\""
        log "Bootstrapped on slot_a at $ver"
    fi
}

check_and_update() {
    init_state_if_missing
    bootstrap

    local current inactive_name inactive_path
    current=$(get_current_slot_name)
    if [ "$current" == "none" ]; then
        log "ERROR: could not determine current slot from symlink"
        exit 1
    fi
    inactive_name=$(other_slot "$current")
    inactive_path=$(slot_path "$inactive_name")

    if [ ! -d "$inactive_path/.git" ]; then
        log "Inactive slot $inactive_name has no checkout yet, cloning"
        git clone --branch "$BRANCH" "$REPO_URL" "$inactive_path"
    fi

    git -C "$inactive_path" fetch origin "$BRANCH" --quiet

    local remote_hash current_hash
    remote_hash=$(git -C "$inactive_path" rev-parse "origin/$BRANCH")
    current_hash=$(state_get current_version)

    if [ "$remote_hash" == "$current_hash" ]; then
        log "Already up to date ($current_hash)"
        state_set ".last_check = \"$(now)\""
        exit 0
    fi

    log "New version found: $remote_hash (current: $current_hash) -> deploying to $inactive_name"
    git -C "$inactive_path" reset --hard "origin/$BRANCH"

    # Optional: dependency install / build step for the new checkout goes here, e.g.
    # if [ -f "$inactive_path/requirements.txt" ]; then
    #     pip3 install --break-system-packages -r "$inactive_path/requirements.txt"
    # fi

    # Record rollback target before flipping, so a crash mid-flip is still recoverable
    state_set ".previous_slot = \"$current\" | .previous_version = \"$current_hash\" | .status = \"updating\" | .last_check = \"$(now)\""

    # Atomic symlink flip
    ln -sfn "$inactive_path" "$CURRENT_LINK.tmp"
    mv -Tf "$CURRENT_LINK.tmp" "$CURRENT_LINK"

    state_set ".current_slot = \"$inactive_name\" | .current_version = \"$remote_hash\" | .status = \"testing\""

    log "Flipped to $inactive_name at $remote_hash, restarting $APP_SERVICE"
    systemctl restart "$APP_SERVICE"

    log "Handing off to watchdog to verify health"
    systemctl start ota-watchdog.service
}

check_and_update
