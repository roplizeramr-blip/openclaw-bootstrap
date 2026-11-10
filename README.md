# openclaw-bootstrap

Idempotent bootstrap for an OpenClaw Gateway on CranL that uses OmniRoute as a
custom OpenAI-compatible provider, with DuckDuckGo web search and a recurring
model-catalog sync.

## What it does

- Sets `gateway.mode=local` only when it is missing (avoids a needless restart)
- Registers the OmniRoute provider (`models.providers.<id>`) from env vars
- Rebuilds the model catalog from OmniRoute `/v1/models` (pinned
  `auto/best-coding` preserved)
- Sets the default and utility models to `<provider>/auto/best-coding`
- Installs and enables the DuckDuckGo web-search plugin
- Creates a `*/30 * * * *` catalog-sync automation (delivery: none)
- Enables password-only Control UI access (`dangerouslyDisableDeviceAuth`) so a
  fresh state directory does not lock the browser out of the terminal

## Required environment variables

| Variable | Example |
| --- | --- |
| `OMNIROUTE_BASE_URL` | `https://omniroute-xxxx.cranl.net/v1` |
| `OMNIROUTE_API_KEY` | `sk-...` |
| `OMNIROUTE_PROVIDER_ID` | optional, defaults to `custom-omniroute-f6bdf863-ay9box-cranl-net` |
| `OPENCLAW_PUBLIC_URL` | optional, used for `gateway.controlUi.allowedOrigins` |

## Recovery after a container restart

The CranL template app has no persistent volume, so `/home/node/.openclaw` is
recreated on every container restart. Run this from the OpenClaw terminal (or
from CranL `run_command`) after a restart:

```sh
curl -fsSL https://raw.githubusercontent.com/roplizeramr-blip/openclaw-bootstrap/main/bootstrap.sh -o /tmp/bootstrap.sh
OMNIROUTE_BASE_URL=https://omniroute-f6bdf863-ay9box.cranl.net/v1 \
OMNIROUTE_API_KEY=sk-c154f78bbae571cd-4900a1-f39c3b3b \
OPENCLAW_PUBLIC_URL=https://openclaw-f8b74315-vbuifw.cranl.net \
sh /tmp/bootstrap.sh
```

The script is safe to run repeatedly. It creates
`/home/node/.openclaw/scripts/omniroute-sync.sh`, which embeds the provider
credentials for the automation, so the scheduled job works even when the
container shell does not inherit CranL environment variables.

## Files

- `bootstrap.sh` — idempotent setup
- `omniroute-model-sync.mjs` — catalog sync (run manually or by the automation)
- `Dockerfile` — optional image that runs bootstrap then the Gateway

## Notes

- The template app cannot be converted to a source/GitHub deploy and has no
  volumes. For durable state, create a Docker app with a volume on
  `/home/node/.openclaw` and a command that runs the bootstrap before the
  Gateway.
- `gateway.controlUi.dangerouslyDisableDeviceAuth` is a deliberate tradeoff for
  this single-user deployment: the Gateway is still password-protected, but a
  browser no longer needs a one-time device-pairing approval after a restart.
