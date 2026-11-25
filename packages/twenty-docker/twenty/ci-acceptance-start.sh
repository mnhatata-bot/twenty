#!/bin/sh
set -eu
: "${PG_DATABASE_URL:?Dedicated PostgreSQL required}"
: "${REDIS_URL:?Dedicated cache required}"
: "${APP_SECRET:?Generated secret required}"
: "${CI_TWENTY_HOSTPORT:?Private acceptance service required}"
export SERVER_URL="http://$CI_TWENTY_HOSTPORT"
export NODE_PORT="${PORT:-10000}"
export IS_BILLING_ENABLED=false
export SIGN_IN_PREFILLED=false
export STORAGE_TYPE=local
mkdir -p /app/packages/twenty-server/.local-storage
chown 1000:1000 /app/packages/twenty-server/.local-storage
# Run native migrations and cron registration before starting the worker.
cd /app/packages/twenty-server
if [ "$(su-exec 1000 psql -tAc "SELECT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'core')" "$PG_DATABASE_URL")" = f ]; then
  su-exec 1000 yarn database:init:prod
fi
su-exec 1000 yarn command:prod cache:flush
su-exec 1000 yarn command:prod upgrade
su-exec 1000 yarn command:prod cache:flush
su-exec 1000 yarn command:prod cron:register:all
su-exec 1000 yarn worker:prod &
worker=$!
su-exec 1000 node dist/main &
web=$!
trap 'kill "$worker" "$web" 2>/dev/null || true' EXIT
# BusyBox shell wait -n supervises both processes.
wait -n "$worker" "$web"
