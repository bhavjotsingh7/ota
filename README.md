# Jetson OTA Update System

Git-pull based OTA with A/B slots, a symlink flip, `state.json` as the
state table, and a systemd watchdog that rolls back a bad deployment
automatically.

## How it works

- `/opt/app/slot_a` and `/opt/app/slot_b` are two git checkouts of your repo.
- `/opt/app/current` is a symlink pointing at whichever slot is live.
- `ota-check.timer` runs `ota_check.sh` every 10 minutes:
  - fetches the inactive slot, compares its commit hash to the current one
  - if there's a new commit: hard-resets the inactive slot to it, flips the
    symlink, restarts `app.service`, then starts `ota-watchdog.service`
- `ota_watchdog.sh` watches the app for 30s after a flip. If the service
  dies or `health_check.sh` fails, it calls `ota_rollback.sh`, which flips
  the symlink back and restarts the app on the previous known-good commit.
- `state.json` tracks `current_slot`, `current_version`, `previous_slot`,
  `previous_version`, and `status` (`stable` / `updating` / `testing` /
  `rolled_back` / `failed`) so you can always tell what's running and
  recover from a crash mid-update.

## Setup

**1. Deploy key on the Jetson** (per your earlier design — SSH deploy key +
git's own SHA hashing, no extra crypto layer needed):

```bash
ssh-keygen -t ed25519 -f ~/.ssh/ota_deploy_key -N ""
cat ~/.ssh/ota_deploy_key.pub
```

Add the public key as a **deploy key** (read-only is fine) on the GitHub
repo, then point git at it, e.g. in `~/.ssh/config`:

```
Host github.com
  IdentityFile ~/.ssh/ota_deploy_key
  IdentitiesOnly yes
```

**2. Copy this folder to the Jetson and run the installer:**

```bash
scp -r ota-system username@ip:~/
ssh username@ip
cd ota-system
./install.sh
```

**3. Edit the two things that are repo/app-specific:**

- `/opt/app/ota/ota_check.sh` — set `REPO_URL` (SSH form, e.g.
  `git@github.com:you/repo.git`) and `BRANCH`.
- `/etc/systemd/system/app.service` — set the real `ExecStart` for your
  application (installed from `app.service.example`, points at
  `/opt/app/current`).

Then:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now app.service
sudo /opt/app/ota/ota_check.sh   # test once manually
journalctl -t ota-check -t ota-watchdog -t ota-rollback -f
```

## Notes

- If your app needs a build/install step after pulling (e.g.
  `pip install -r requirements.txt`), add it in `ota_check.sh` where
  marked — it runs against the *inactive* slot before the symlink flips,
  so a slow install never affects the live app.
- `health_check.sh` just checks the systemd unit is active by default.
 
- Rollback is fully automatic on a bad deploy, but you can also run
  `sudo /opt/app/ota/ota_rollback.sh` manually at any time.
- `state.json` lives at `/opt/app/state.json` if you want to inspect or
  reset it by hand.
