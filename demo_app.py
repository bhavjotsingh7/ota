#!/usr/bin/env python3
# demo_app.py - OTA demo application.
# Prints its own version every 2 seconds so an update or rollback
# is immediately visible in the logs.
import time
import subprocess

VERSION = "1.0"

def get_commit_hash():
    try:
        out = subprocess.check_output(
            ["git", "rev-parse", "--short", "HEAD"],
            cwd="/opt/app/current"
        )
        return out.decode().strip()
    except Exception:
        return "unknown"

if __name__ == "__main__":
    commit = get_commit_hash()
    while True:
        print(f"[demo-app] VERSION={VERSION} commit={commit}", flush=True)
        time.sleep(2)
