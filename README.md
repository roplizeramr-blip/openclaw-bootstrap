# openclaw-bootstrap

Idempotent bootstrap and durable container startup for OpenClaw on CranL,
using OmniRoute as a custom OpenAI-compatible provider, DuckDuckGo web search,
and a recurring model-catalog sync.

## What is in this repo

- `Dockerfile` — image that builds on `ghcr.io/openclaw/openclaw:2026.11.2`
- `prepare-config.mjs` — writes a minimal, complete gateway config **before**
  the gateway starts (local mode, LAN bind, password auth, password-only
  Control UI access, admin-http-rpc enabled), so no post-boot restart is needed
- `start.sh` — startup: prepare-config, then the idempotent bootstrap, then the
  gateway
- `bootstrap.sh` — one-shot setup: OmniRoute provider + live catalog from
  `/v1/models` (pinned `auto/best-coding` preserved), DuckDuckGo search,
  catalog-sync automation
- `omniroute-model-sync.mjs` — catalog sync (run by the automation every
  30 minutes, or manually)

## Deploy on CranL

1. Create a Docker image app from this repo (or run `start.sh` semantics).
2. Attach a **named volume** on `/home/node/.openclaw` (this is the gateway
   state directory; without it, all config is lost on every redeploy).
3. Set environment variables:

| Variable | Required | Purpose |
| --- | --- | --- |
| `OMNIROUTE_BASE_URL` | yes | e.g. `https://<omniroute-host>/v1` |
| `OMNIROUTE_API_KEY` | yes | OmniRoute API key |
| `OPENCLAW_GATEWAY_PASSWORD` | yes | Gateway password (Control UI login) |
| `OPENCLAW_PUBLIC_URL` | yes | e.g. `https://<app>.cranl.net` (Control UI origin) |
| `OMNIROUTE_PROVIDER_ID` | no | defaults to the current custom provider id |

The container is safe to restart: every boot re-runs the idempotent bootstrap,
and the named volume keeps `openclaw.json`, the catalog, installed plugins,
and automations across restarts and redeploys.

## Recovery (fresh volume or lost state)

Everything is rebuilt automatically on boot. If automation creation fails on
first boot (the gateway is not up yet while the bootstrap runs), add it once
after the gateway is live:

```
POST /api/v1/admin/rpc
Authorization: Bearer <OPENCLAW_GATEWAY_PASSWORD>
{ "method": "cron.add", "params": {
  "name": "OmniRoute model catalog sync",
  "schedule": { "kind": "cron", "expr": "*/30 * * * *" },
  "sessionTarget": "isolated",
  "wakeMode": "now",
  "payload": { "kind": "command", "argv": ["sh", "/home/node/.openclaw/scripts/omniroute-sync.sh"], "timeoutSeconds": 300 },
  "delivery": { "mode": "none" }
} }
```

## Notes

- `gateway.controlUi.dangerouslyDisableDeviceAuth` is a deliberate single-user
  tradeoff: the gateway stays password-protected, but a browser no longer needs
  a one-time device-pairing approval after a restart.
- Custom providers require explicit model entries; the sync automation keeps
  OpenClaw's catalog aligned with OmniRoute's `/v1/models` every 30 minutes.
- Settings → Models (`/settings/model-providers`) can add/edit providers and
  keys from the Control UI (`Connect provider`, `Set API key`, `Remove key`,
  `Configure models`). The "Test connection" probe may report
  "Invalid response" even when the provider works; verify with a real chat.
