#!/bin/bash
# health_check.sh
# Customize this for your actual application. Exit 0 = healthy,
# non-zero = unhealthy. Called repeatedly by the watchdog during
# the grace period after a new deployment.
#
# Default: just require the systemd service to still be active.
# Better options once your app has one:
#   - curl -sf http://localhost:PORT/health
#   - check a PID file / process is alive and not zombied
#   - check camera devices are still enumerated (for the stereo pipeline)

systemctl is-active --quiet app.service
