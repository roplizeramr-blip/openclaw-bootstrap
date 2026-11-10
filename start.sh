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

STATE_HINT=""
for d in /home/node/.openclaw/tmp/openclaw-* /home/node/.openclaw/state/tmp/openclaw-*; do
  if [ -d "$d" ]; then
    STATE_HINT="$STATE_HINT $d"
  fi
done
if [ -n "$STATE_HINT" ]; then
  i=0
  while [ "$i" -lt 120 ]; do
    fresh=""
    for d in $STATE_HINT; do
      fresh=$(find "$d" -maxdepth 2 -type f -newermt "@$(( $(date +%s) - 95 ))" -print -quit 2>/dev/null)
      [ -n "$fresh" ] && break
    done
    [ -z "$fresh" ] && break
    echo "waiting for previous gateway heartbeat to go stale (round $i: $fresh)..."
    i=$((i + 1))
    sleep 5
  done
elif [ -f /home/node/.openclaw/state/openclaw.sqlite ]; then
  # Lock dir name unknown (different uid); a previous gateway existed on this
  # volume, so wait out the 90s heartbeat window rather than risk admission failure.
  echo "previous state found; waiting 100s for any foreign gateway heartbeat to age out..."
  sleep 100
fi

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
