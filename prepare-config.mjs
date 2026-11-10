import fs from "node:fs";

const path = "/home/node/.openclaw/openclaw.json";
let cfg = {};
try {
  cfg = JSON.parse(fs.readFileSync(path, "utf8"));
} catch {
  cfg = {};
}

cfg.gateway = cfg.gateway || {};
cfg.gateway.mode = "local";
cfg.gateway.bind = "lan";
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

fs.writeFileSync(path, JSON.stringify(cfg, null, 2));
console.log("prepared gateway config");
