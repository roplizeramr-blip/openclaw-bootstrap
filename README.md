# openclaw-bootstrap

Durable OpenClaw deployment for CranL: a Docker image built from this repo that
boots a self-configuring OpenClaw Gateway with OmniRoute as a custom
OpenAI-compatible provider, DuckDuckGo web search, and a recurring
model-catalog sync. A named volume keeps all state across restarts.

## Layout

- `Dockerfile` — thin image on `ghcr.io/openclaw/openclaw:2026.11.2`, runs `start.sh`
- `start.sh` — startup: seed a minimal config if missing, wait out a foreign-namespace
  gateway heartbeat (previous owner; prevents admission failure), run the idempotent
  bootstrap, exec the gateway
- `bootstrap.sh` — idempotent setup (safe to re-run): gateway mode/bind, password auth,
  password-only Control UI access, `trustedProxies` + `allowRealIpFallback` (CranL
  ingress compatibility), OmniRoute provider + live catalog, DuckDuckGo, admin-http-rpc,
  sync automation
- `omniroute-model-sync.mjs` — syncs the provider catalog from OmniRoute `/v1/models`
  (run by the automation every 30 minutes, or manually)

## Deploy on CranL

1. Create a Docker app from this repo (`build: dockerfile`), port `18789`, region any.
2. Attach a **named volume** on `/home/node/.openclaw` (the gateway state directory).
3. Set environment variables (see below).
4. Verify: `https://<app>.cranl.net/health` returns `{"ok":true,"status":"live"}`.

### Redeploy protocol (learned the hard way)

CranL's rolling deploy starts the new container while the previous gateway may
still hold the shared state lock. The new gateway then fails admission and dies.
To deploy reliably:

1. `app_lifecycle({ action: "stop" })` — clean SIGTERM, releases the heartbeat
2. wait ~2 minutes (the sidecar heartbeat must age out)
3. `deploy_app` — the new container boots, admission passes, bootstrap re-applies
   config idempotently
4. `/health` 200 + Control UI at `/`

The start.sh sidecar wait makes plain `restart` self-healing as well: the new
container blocks until the previous owner's heartbeat is 95+ seconds stale.

## Environment variables

| Variable | Required | Purpose |
| --- | --- | --- |
| `OMNIROUTE_BASE_URL` | yes | e.g. `https://<omniroute-host>/v1` |
| `OMNIROUTE_API_KEY` | yes | OmniRoute API key |
| `OPENCLAW_GATEWAY_PASSWORD` | yes | Gateway password (Control UI login, admin-http-rpc) |
| `OPENCLAW_PUBLIC_URL` | yes | e.g. `https://<app>.cranl.net` (Control UI allowed origin) |
| `OPENCLAW_RESET_CONFIG` | no | `1` on first boot to wipe a poisoned openclaw.json; unset after |
| `OMNIROUTE_PROVIDER_ID` | no | provider id override |

## What you get

- 44+ models from OmniRoute's live catalog (sync every 30 min), visible in the
  Control UI picker; default model `<provider>/auto/best-coding`
- DuckDuckGo web search (plugin) wired to `tools.web.search`
- Password-only Control UI access (no device pairing needed after restarts)
- `admin-http-rpc` on `POST /api/v1/admin/rpc` (Bearer = gateway password) for
  operator automation (health, config.get/patch, cron.list/add/run, ...)
- Catalog sync automation: `*/30 * * * *`, delivery: none

## Verification

```sh
curl https://<app>.cranl.net/health
curl -X POST https://<app>.cranl.net/api/v1/admin/rpc \
  -H "Authorization: Bearer <OMNIROUTE_PASSWORD>" \
  -H "Content-Type: application/json" \
  -d '{"method":"config.get","params":{}}'
```

Expected: `/health` → `{"ok":true,"status":"live"}`; `config.get` → provider with N models.

## Notes

- The CranL proxy ingress peer/XFF chain is not usable with narrow CIDRs, so the
  gateway runs with `gateway.trustedProxies: ["0.0.0.0/0","::/0"]` and
  `gateway.allowRealIpFallback: true`. Attribution only feeds rate limiting and
  logs; password auth still gates everything.
- Settings → Models can add/edit providers from the UI (Connect provider,
  Set/Remove key). Custom providers require explicit model entries, which the
  sync automation maintains.
- A fresh volume is fully rebuilt by the bootstrap on first boot; a warm volume
  is only additively modified.
