#!/bin/bash
set -euo pipefail

# Default to 10 minutes (600s) if not set in .env
: "${UPDATE_FREQUENCY:=600}"

echo "[entrypoint] Running /app/update-ip.sh every ${UPDATE_FREQUENCY}s\n"

while true; do
  echo "[entrypoint] Starting update-ip.sh at $(date)\n"
  /app/update-ip.sh
  echo "[entrypoint] Finished run, sleeping for ${UPDATE_FREQUENCY}s\n"
  sleep "$UPDATE_FREQUENCY"
done