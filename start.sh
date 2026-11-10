#!/bin/sh
# Durable OpenClaw startup for the CranL Docker app.
# 1) prepare-config (direct file writes; no CLI) writes a complete gateway
#    config BEFORE the gateway starts, so a fresh volume boots fully configured;
# 2) once the gateway is healthy, the idempotent GitHub bootstrap re-runs as a
#    post-start enrichment (installs DuckDuckGo if missing, syncs the catalog,
#    creates the 30-minute sync automation) - CLI works there because the
#    gateway is live in the same container;
# 3) exec the gateway as the container's main process.
set -u
mkdir -p /home/node/.openclaw
node /app/prepare-config.mjs || echo "WARN: prepare-config failed"

if curl -fsSL https://raw.githubusercontent.com/roplizeramr-blip/openclaw-bootstrap/main/bootstrap.sh -o /tmp/bootstrap.sh; then
  (
    i=0
    while [ "$i" -lt 120 ]; do
      curl -sf http://127.0.0.1:18789/health >/dev/null 2>&1 && break
      i=$((i + 1))
      sleep 2
    done
    sh /tmp/bootstrap.sh || echo "WARN: post-start bootstrap failed"
  ) &
else
  echo "WARN: bootstrap download failed; continuing with prepared config"
fi

exec node /app/openclaw.mjs gateway
