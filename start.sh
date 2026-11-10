#!/bin/sh
# Durable OpenClaw startup for the CranL Docker app.
# Flow (battle-tested on a fresh volume at 2026-11-10 12:04):
#   1) seed a minimal config if none exists;
#   2) wait out a foreign-namespace live-owner heartbeat (the previous gateway
#      renews its sidecar every 15s and forfeits custody 90s after its last
#      beat; starting sooner makes admission fail and kill the container);
#   3) run the idempotent bootstrap (CLI-based; the CLI validates every write);
#   4) exec the gateway as the container's main process.
set -u
STATE=/home/node/.openclaw
mkdir -p "$STATE"

[ -f "$STATE/openclaw.json" ] || printf '{"gateway":{"mode":"local"}}\n' > "$STATE/openclaw.json"

# One-time escape hatch: if the config file was poisoned by crash-loop boots,
# deleting it lets the bootstrap rebuild a clean config from scratch.
# Session/state data (openclaw.sqlite) is untouched.
if [ "${OPENCLAW_RESET_CONFIG:-0}" = "1" ]; then
  echo "OPENCLAW_RESET_CONFIG=1: removing openclaw.json for a clean rebuild"
  rm -f "$STATE/openclaw.json"
  printf '{"gateway":{"mode":"local"}}\n' > "$STATE/openclaw.json"
fi

for d in "$STATE/state/tmp" "$STATE/tmp"; do
  [ -d "$d" ] || continue
  i=0
  while [ "$i" -lt 120 ]; do
    fresh=$(find "$d" -maxdepth 3 -type f -newermt "@$(( $(date +%s) - 95 ))" -print -quit 2>/dev/null)
    [ -z "$fresh" ] && break
    echo "waiting for previous gateway heartbeat to go stale (round $i)..."
    i=$((i + 1))
    sleep 5
  done
done

curl -fsSL https://raw.githubusercontent.com/roplizeramr-blip/openclaw-bootstrap/main/bootstrap.sh -o /tmp/bootstrap.sh || echo "WARN: bootstrap download failed"
if [ -f /tmp/bootstrap.sh ]; then
  sh /tmp/bootstrap.sh || echo "WARN: bootstrap failed; starting gateway with existing config"
fi

(
  # Automation creation needs the live gateway WS; post-start only.
  sleep 90
  i=0
  while [ "$i" -lt 150 ]; do
    curl -sf http://127.0.0.1:18789/health >/dev/null 2>&1 && break
    i=$((i + 1))
    sleep 2
  done
  sh /tmp/bootstrap.sh || echo "WARN: post-start bootstrap failed"
) &

exec node /app/openclaw.mjs gateway
