// Durable OpenClaw container preparation for CranL.
// Runs BEFORE the gateway starts and only uses direct file writes + HTTP
// fetches (no `openclaw` CLI), so it works on a fresh volume and even when a
// previous gateway's heartbeat is stale. Idempotent: merges the existing
// config and preserves the OmniRoute provider if the live catalog cannot be
// fetched right now.
import fs from "node:fs";
import path from "node:path";

const HOME = "/home/node/.openclaw";
const PATH_ = path.join(HOME, "openclaw.json");
const PROVIDER = process.env.OMNIROUTE_PROVIDER_ID || "custom-omniroute-f6bdf863-ay9box-cranl-net";
const PINNED = "auto/best-coding";
const PINNED_ENTRY = {
  id: PINNED,
  name: "auto/best-coding (Custom Provider)",
  reasoning: false,
  input: ["text"],
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
  contextWindow: 128000,
  maxTokens: 4096,
  api: "openai-completions",
};
const num = (v) => (typeof v === "number" && Number.isFinite(v) ? v : undefined);

function loadConfig() {
  try {
    const raw = fs.readFileSync(PATH_, "utf8");
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === "object") return parsed;
  } catch {}
  return {};
}

function costOf(m) {
  const p = m.pricing || {};
  return {
    input: num(p.input) ?? 0,
    output: num(p.output) ?? 0,
    cacheRead: num(p.cached) ?? 0,
    cacheWrite: num(p.cache_creation) ?? 0,
  };
}

function toEntry(m) {
  const caps = m.capabilities || {};
  const modalities =
    Array.isArray(m.input_modalities) && m.input_modalities.length
      ? m.input_modalities
      : caps.vision
        ? ["text", "image"]
        : ["text"];
  const entry = {
    id: m.id,
    name: typeof m.name === "string" && m.name.trim() ? m.name.trim() : m.id,
    reasoning: Boolean(caps.reasoning),
    input: modalities,
    cost: costOf(m),
    api: "openai-completions",
  };
  const contextWindow = num(m.context_length) ?? num(m.max_input_tokens);
  if (contextWindow) entry.contextWindow = contextWindow;
  const maxTokens = num(m.max_output_tokens);
  if (maxTokens) entry.maxTokens = maxTokens;
  return entry;
}

async function fetchCatalog(base, key) {
  const res = await fetch(`${base}/models`, {
    headers: { Authorization: `Bearer ${key}`, Accept: "application/json" },
    signal: AbortSignal.timeout(20000),
  });
  if (!res.ok) throw new Error(`catalog fetch HTTP ${res.status}`);
  const body = await res.json();
  const catalog = Array.isArray(body.data)
    ? body.data.filter((m) => m && typeof m.id === "string" && m.id.length > 0)
    : [];
  if (catalog.length === 0) throw new Error("catalog empty");
  const seen = new Set();
  const entries = [];
  for (const m of catalog) {
    if (seen.has(m.id)) continue;
    seen.add(m.id);
    entries.push(toEntry(m));
  }
  if (!seen.has(PINNED)) entries.unshift(PINNED_ENTRY);
  return entries;
}

const cfg = loadConfig();

cfg.gateway = cfg.gateway || {};
cfg.gateway.mode = "local";
cfg.gateway.bind = "lan";
cfg.gateway.trustedProxies = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"];
cfg.gateway.auth = { ...(cfg.gateway.auth || {}), mode: "password" };
if (process.env.OPENCLAW_GATEWAY_PASSWORD) {
  cfg.gateway.auth.password = process.env.OPENCLAW_GATEWAY_PASSWORD;
}
cfg.gateway.controlUi = {
  ...(cfg.gateway.controlUi || {}),
  dangerouslyDisableDeviceAuth: true,
};
if (process.env.OPENCLAW_PUBLIC_URL) {
  cfg.gateway.controlUi.allowedOrigins = [process.env.OPENCLAW_PUBLIC_URL];
}

cfg.plugins = cfg.plugins || {};
cfg.plugins.entries = cfg.plugins.entries || {};
cfg.plugins.entries["admin-http-rpc"] = {
  ...(cfg.plugins.entries["admin-http-rpc"] || {}),
  enabled: true,
};

const BASE = process.env.OMNIROUTE_BASE_URL || "";
const KEY = process.env.OMNIROUTE_API_KEY || "";
const MODEL = `${PROVIDER}/${PINNED}`;
if (BASE && KEY) {
  cfg.models = cfg.models || {};
  cfg.models.providers = cfg.models.providers || {};
  const existing = cfg.models.providers[PROVIDER] || {};
  let models = existing.models;
  try {
    models = await fetchCatalog(BASE, KEY);
  } catch (err) {
    if (!Array.isArray(models) || models.length === 0) {
      models = [PINNED_ENTRY];
    }
    console.error(`WARN: catalog fetch failed (${err.message}); keeping previous/pinned models`);
  }
  cfg.models.providers[PROVIDER] = {
    baseUrl: BASE,
    apiKey: KEY,
    api: "openai-completions",
    models,
  };
  cfg.agents = cfg.agents || {};
  cfg.agents.defaults = { ...(cfg.agents.defaults || {}), model: MODEL, utilityModel: MODEL };
  cfg.agents.entries = {
    ...(cfg.agents.entries || {}),
    main: { ...((cfg.agents.entries || {}).main || {}), model: MODEL },
  };
} else {
  console.error("WARN: OMNIROUTE_BASE_URL/OMNIROUTE_API_KEY not set; provider untouched");
}

cfg.tools = cfg.tools || {};
cfg.tools.web = {
  ...(cfg.tools.web || {}),
  search: { enabled: true, provider: "duckduckgo" },
};

fs.mkdirSync(HOME, { recursive: true });
fs.writeFileSync(PATH_, JSON.stringify(cfg, null, 2));
console.log(
  `prepared gateway config (models: ${cfg.models?.providers?.[PROVIDER]?.models?.length ?? "unchanged"})`,
);
