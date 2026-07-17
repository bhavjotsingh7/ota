#!/bin/bash
# install.sh
# Deploys the OTA scripts and systemd units. Run this from inside the
# extracted ota-system directory on the Jetson.

set -euo pipefail

APP_ROOT="/opt/app"
OTA_DIR="$APP_ROOT/ota"

echo "Checking for jq..."
if ! command -v jq >/dev/null 2>&1; then
    echo "Installing jq..."
    sudo apt-get update && sudo apt-get install -y jq
fi

echo "Installing OTA scripts into $OTA_DIR ..."
sudo mkdir -p "$OTA_DIR"
sudo cp ota_check.sh ota_watchdog.sh ota_rollback.sh health_check.sh "$OTA_DIR/"
sudo chmod +x "$OTA_DIR"/*.sh

echo "Installing systemd units..."
sudo cp ota-check.service ota-check.timer ota-watchdog.service /etc/systemd/system/

if [ ! -f /etc/systemd/system/app.service ]; then
    sudo cp app.service.example /etc/systemd/system/app.service
    echo "Installed app.service.example as /etc/systemd/system/app.service — EDIT THIS before enabling it."
else
    echo "/etc/systemd/system/app.service already exists, leaving it untouched."
fi

sudo systemctl daemon-reload
sudo systemctl enable --now ota-check.timer

cat <<EOF

Done. Next steps:
  1. Edit $OTA_DIR/ota_check.sh: set REPO_URL and BRANCH.
  2. Edit /etc/systemd/system/app.service: set the real ExecStart for your app.
  3. (Optional) Edit $OTA_DIR/health_check.sh with a real health check.
  4. sudo systemctl daemon-reload
  5. sudo systemctl enable --now app.service
  6. Test manually once:  sudo $OTA_DIR/ota_check.sh
  7. Watch logs:  journalctl -t ota-check -t ota-watchdog -t ota-rollback -f
EOF
