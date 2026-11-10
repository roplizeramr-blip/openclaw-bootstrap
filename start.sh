#!/bin/sh
# Durable OpenClaw startup for the CranL Docker app.
# 1) writes a minimal, complete gateway config (gateway local, password auth,
#    device-pairing bypass for the Control UI, admin-http-rpc enabled) BEFORE
#    the gateway reads it, so no restart is needed after first boot;
# 2) runs the idempotent GitHub bootstrap (OmniRoute provider + live catalog,
#    DuckDuckGo search, sync automation) which is safe to re-run on every boot;
# 3) execs the gateway.
set -u
mkdir -p /home/node/.openclaw
node /app/prepare-config.mjs
if curl -fsSL https://raw.githubusercontent.com/roplizeramr-blip/openclaw-bootstrap/main/bootstrap.sh -o /tmp/bootstrap.sh; then
  sh /tmp/bootstrap.sh || echo "WARN: bootstrap run failed"
else
  echo "WARN: bootstrap download failed; starting gateway with minimal config"
fi
exec node /app/openclaw.mjs gateway
