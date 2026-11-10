FROM ghcr.io/openclaw/openclaw:2026.11.2
ENV OPENCLAW_BOOTSTRAP_URL=https://raw.githubusercontent.com/roplizeramr-blip/openclaw-bootstrap/main/bootstrap.sh
CMD ["sh","-lc","cd /app && curl -fsSL \"$OPENCLAW_BOOTSTRAP_URL\" -o /tmp/bootstrap.sh && BOOTSTRAP_RAW_BASE=https://raw.githubusercontent.com/roplizeramr-blip/openclaw-bootstrap/main sh /tmp/bootstrap.sh && exec node /app/openclaw.mjs gateway"]
