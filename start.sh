#!/bin/sh
set -u
mkdir -p /home/node/.openclaw
node /app/prepare-config.mjs
exec node /app/openclaw.mjs gateway
