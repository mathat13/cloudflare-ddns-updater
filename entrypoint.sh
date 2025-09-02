#!/bin/sh
: "${CRON_SCHEDULE:="*/10 * * * *"}"
echo "$CRON_SCHEDULE /app/update-ip.sh > /proc/1/fd/1 2>&1" > /etc/cron.d/dns-updater
crond -f -l 2