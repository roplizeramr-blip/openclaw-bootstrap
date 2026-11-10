FROM ghcr.io/openclaw/openclaw:2026.11.2
COPY start.sh /app/start.sh
CMD ["sh", "/app/start.sh"]
