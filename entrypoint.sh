#!/bin/bash
set -euo pipefail

# Default to 10 minutes (600s) if not set in .env
: "${UPDATE_FREQUENCY:=300}"

echo -e "\e[33m[entrypoint] Running /app/update-ip.sh every ${UPDATE_FREQUENCY}s\n\e[0m"

while true; do
  echo -e "\e[33m[entrypoint] Starting update-ip.sh at $(date)\n\e[0m"
  /app/update-ip.sh
  echo -e "\e[33m[entrypoint] Finished run, sleeping for ${UPDATE_FREQUENCY}s\n\e[0m"
  sleep "$UPDATE_FREQUENCY"
done