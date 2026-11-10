FROM ghcr.io/openclaw/openclaw:2026.11.2
COPY start.sh /app/start.sh
COPY prepare-config.mjs /app/prepare-config.mjs
CMD ["sh", "/app/start.sh"]
