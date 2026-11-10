#!/usr/bin/env node
// Keep OpenClaw's OmniRoute provider catalog in sync with OmniRoute's /v1/models.
// Adds new models, refreshes metadata, removes models OmniRoute no longer serves,
// and preserves the pinned auto/best-coding route that /v1/models does not list.
// Modalities are filtered to OpenClaw's allowlist (text, image, video, audio)
// because OmniRoute may advertise values OpenClaw rejects with INVALID_REQUEST.
import { execFileSync } from "node:child_process";

const BASE = process.env.OMNIROUTE_BASE_URL || "https://omniroute-f6bdf863-ay9box.cranl.net/v1";
const KEY = process.env.OMNIROUTE_API_KEY || "";
const PROVIDER = process.env.OMNIROUTE_PROVIDER_ID || "custom-omniroute-f6bdf863-ay9box-cranl-net";
const PINNED_ID = "auto/best-coding";

const ALLOWED_INPUT = ["text", "image", "video", "audio"];

const num = (v) => (typeof v === "number" && Number.isFinite(v) ? v : undefined);

function sanitizeModalities(input) {
  const keep = Array.isArray(input)
    ? input.filter((v) => typeof v === "string" && ALLOWED_INPUT.includes(v.toLowerCase()))
    : [];
  const unique = [...new Set(keep.map((v) => v.toLowerCase()))];
  return unique.length ? unique : ["text"];
}

function oc(args) {
  const opts = { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], timeout: 180000 };
  const explicit = process.env.OPENCLAW_BIN;
  if (explicit) return execFileSync(explicit, args, opts);
  try {
    return execFileSync("openclaw", args, opts);
  } catch (err) {
    if (err && err.code === "ENOENT") {
      return execFileSync(process.execPath, ["/app/openclaw.mjs", ...args], opts);
    }
    throw err;
  }
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
      ? sanitizeModalities(m.input_modalities)
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

function readCurrent() {
  try {
    const out = oc(["config", "get", `models.providers.${PROVIDER}.models`]);
    const parsed = JSON.parse(out);
    if (!Array.isArray(parsed)) return [];
    // Heal previously-synced entries whose modalities are outside the allowlist.
    return parsed.map((m) => ({ ...m, input: sanitizeModalities(m.input) }));
  } catch (err) {
    console.error(`could not read current catalog: ${err.message}`);
    return [];
  }
}

if (!KEY) {
  console.error("OMNIROUTE_API_KEY is not set");
  process.exit(1);
}

const res = await fetch(`${BASE}/models`, {
  headers: { Authorization: `Bearer ${KEY}`, Accept: "application/json" },
});
if (!res.ok) {
  console.error(`catalog fetch failed: HTTP ${res.status}`);
  process.exit(1);
}
const body = await res.json();
const catalog = Array.isArray(body.data)
  ? body.data.filter((m) => m && typeof m.id === "string" && m.id.length > 0)
  : [];
if (catalog.length === 0) {
  console.error("catalog empty; refusing to overwrite the provider catalog");
  process.exit(1);
}

const current = readCurrent();
const byId = new Map(
  current.filter((m) => m && typeof m.id === "string").map((m) => [m.id, m]),
);

const entries = [];
const seen = new Set();
for (const m of catalog) {
  if (seen.has(m.id)) continue;
  seen.add(m.id);
  const fresh = toEntry(m);
  const prev = byId.get(m.id);
  entries.push(prev ? { ...prev, ...fresh, input: fresh.input } : fresh);
}

const pinnedFromCatalog = seen.has(PINNED_ID);
if (!pinnedFromCatalog) {
  entries.unshift(
    byId.get(PINNED_ID) || {
      id: PINNED_ID,
      name: "auto/best-coding (Custom Provider)",
      reasoning: false,
      input: ["text"],
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
      contextWindow: 128000,
      maxTokens: 4096,
      api: "openai-completions",
    },
  );
}

oc([
  "config",
  "set",
  `models.providers.${PROVIDER}.models`,
  JSON.stringify(entries),
  "--strict-json",
  "--replace",
]);

console.log(
  `OmniRoute catalog sync OK: ${entries.length} models (catalog ${catalog.length}; pinned auto/best-coding ${pinnedFromCatalog ? "from catalog" : "preserved"})`,
);
