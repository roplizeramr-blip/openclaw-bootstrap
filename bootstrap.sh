#!/bin/sh
# Idempotent OpenClaw bootstrap for CranL.
# Ensures: gateway mode, OmniRoute provider + live model catalog, DuckDuckGo web search,
# and the recurring catalog-sync automation. Safe to run on every container start.
set -u

BASE="${OMNIROUTE_BASE_URL:-}"
KEY="${OMNIROUTE_API_KEY:-}"
PROVIDER="${OMNIROUTE_PROVIDER_ID:-custom-omniroute-f6bdf863-ay9box-cranl-net}"
MODEL="$PROVIDER/auto/best-coding"
STATE=/home/node/.openclaw
SYNC="$STATE/scripts/omniroute-model-sync.mjs"
WRAPPER="$STATE/scripts/omniroute-sync.sh"
RAW="${BOOTSTRAP_RAW_BASE:-https://raw.githubusercontent.com/roplizeramr-blip/openclaw-bootstrap/main}"
PUBLIC_URL="${OPENCLAW_PUBLIC_URL:-}"

oc() {
  if command -v openclaw >/dev/null 2>&1; then
    openclaw "$@"
  else
    node /app/openclaw.mjs "$@"
  fi
}

mkdir -p "$STATE/scripts"

curl -fsSL "$RAW/omniroute-model-sync.mjs" -o "$SYNC" || echo "WARN: could not download sync script"
curl -fsSL "$RAW/bootstrap.sh" -o "$STATE/scripts/bootstrap.sh" 2>/dev/null && chmod +x "$STATE/scripts/bootstrap.sh" || true

echo "== gateway mode =="
CURRENT_MODE=$(oc config get gateway.mode 2>/dev/null | tr -d '"' || true)
if [ "$CURRENT_MODE" != "local" ]; then
  oc config set gateway.mode local || echo "WARN: gateway.mode write failed"
fi
CURRENT_BIND=$(oc config get gateway.bind 2>/dev/null | tr -d '"' || true)
if [ -z "$CURRENT_BIND" ]; then
  oc config set gateway.bind lan || echo "WARN: gateway.bind write failed"
fi
if [ -n "$PUBLIC_URL" ]; then
  oc config set gateway.controlUi.allowedOrigins "[\"$PUBLIC_URL\"]" --strict-json --replace || echo "WARN: allowedOrigins write failed"
fi
# Password-only browser access avoids a pairing lockout after a fresh state dir.
oc config set gateway.controlUi.dangerouslyDisableDeviceAuth true || echo "WARN: device-auth flag write failed"
if [ -n "${OPENCLAW_GATEWAY_PASSWORD:-}" ]; then
  oc config set gateway.auth.mode password || echo "WARN: auth mode write failed"
  oc config set gateway.auth.password "$OPENCLAW_GATEWAY_PASSWORD" || echo "WARN: auth password write failed"
fi

if [ -n "$BASE" ] && [ -n "$KEY" ]; then
  echo "== provider =="
  oc config set "models.providers.$PROVIDER" "{\"baseUrl\":\"$BASE\",\"apiKey\":\"$KEY\",\"api\":\"openai-completions\",\"models\":[]}" --strict-json --replace || echo "WARN: provider write failed"
  echo "== catalog sync =="
  if [ -f "$SYNC" ]; then node "$SYNC" || echo "WARN: catalog sync failed"; fi
  echo "== agent defaults =="
  oc config set agents.defaults.model "$MODEL" || true
  oc config set agents.defaults.utilityModel "$MODEL" || true
  oc config set agents.entries.main.model "$MODEL" 2>/dev/null || true

  cat > "$WRAPPER" <<EOF
#!/bin/sh
export OMNIROUTE_BASE_URL="$BASE"
export OMNIROUTE_API_KEY="$KEY"
exec node "$SYNC"
EOF
  chmod +x "$WRAPPER"
else
  echo "WARN: OMNIROUTE_BASE_URL / OMNIROUTE_API_KEY not set; skipping provider setup"
fi

echo "== web search =="
if ! oc plugins list 2>/dev/null | grep -qi 'duckduckgo'; then
  oc plugins install @openclaw/duckduckgo-plugin || echo "WARN: duckduckgo install failed"
fi
oc config set tools.web.search.provider duckduckgo || true
oc config set tools.web.search.enabled true || true

echo "== automation =="
if ! oc automations list 2>/dev/null | grep -q 'OmniRoute model catalog sync'; then
  oc automations create "*/30 * * * *" --name "OmniRoute model catalog sync" --command "sh $WRAPPER" --timeout-seconds 300 || true
  JOB_ID=$(oc automations list 2>/dev/null | awk '/OmniRoute model catalog sync/ {print $1; exit}')
  if [ -n "${JOB_ID:-}" ]; then
    oc automations edit "$JOB_ID" --no-deliver || true
  fi
fi

echo "bootstrap complete: $(oc config get agents.defaults.model 2>/dev/null || echo unknown)"
