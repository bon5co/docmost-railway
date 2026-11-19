#!/bin/sh
# Railway boot for Docmost.
#
# Refuses to start without a strong admin password, an application secret and the database and Redis settings, builds the
# connection strings and the public address from Railway's variables, makes the storage volume writable for upstream's uid,
# creates the first workspace and its administrator (upstream's one-time setup call, which answers 403 once a workspace exists),
# then runs the server as uid 1000.
set -u
APP_SECRET="${APP_SECRET:-}"
fail() { echo "[railway] $1" >&2; exit 1; }
[ -n "${ADMIN_PASSWORD:-}" ] || fail "ADMIN_PASSWORD is not set; refusing to start a wiki with no admin login and an open setup page"
[ "${#ADMIN_PASSWORD}" -ge 12 ] || fail "ADMIN_PASSWORD must be at least 12 characters"
[ "${#ADMIN_PASSWORD}" -le 70 ] || fail "ADMIN_PASSWORD must be at most 70 characters"
[ -n "${ADMIN_EMAIL:-}" ] || fail "ADMIN_EMAIL is not set"
[ "${#APP_SECRET}" -ge 32 ] || fail "APP_SECRET must be set and at least 32 characters"
for v in POSTGRES_HOST POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB REDIS_HOST REDIS_PASSWORD; do
  eval "val=\${$v:-}"
  [ -n "$val" ] || fail "$v is not set"
done
case "${PORT:=8080}" in ''|*[!0-9]*) fail "PORT must be a number, got '$PORT'";; esac
if [ -z "${APP_URL:-}" ]; then
  [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ] || fail "neither APP_URL nor RAILWAY_PUBLIC_DOMAIN is set"
  APP_URL="https://$RAILWAY_PUBLIC_DOMAIN"
fi
# family=0 lets ioredis resolve Railway's private names over IPv4 or IPv6; its default of 4 fails on an IPv6-only private network
export APP_URL PORT HOST=0.0.0.0 HOME=/home/node
export DATABASE_URL="postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:5432/$POSTGRES_DB"
export REDIS_URL="redis://:$REDIS_PASSWORD@$REDIS_HOST:6379?family=0"

esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
BODY="{\"name\":\"Admin\",\"email\":\"$(esc "$ADMIN_EMAIL")\",\"password\":\"$(esc "$ADMIN_PASSWORD")\",\"workspaceName\":\"Docmost\"}"

echo "[railway] Docmost on :$PORT as $APP_URL, postgres $POSTGRES_HOST, redis $REDIS_HOST, uid=$(id -u) storage owner before=$(stat -c %u:%g /app/data/storage)"
if [ "$(id -u)" = 0 ]; then
  chown -R 1000:1000 /app/data || fail "could not hand /app/data to uid 1000"
  echo "[railway] storage owner after=$(stat -c %u:%g /app/data/storage)"
fi

# One-time setup, once the server answers. Upstream refuses it with 403 when a workspace exists, so a redeploy leaves the owner's
# changed password alone. The server is the only thing that can create the first account, and its setup page is open to the first
# visitor until this runs, so it runs as soon as the process is up.
(
  n=0
  until curl -fsS -o /dev/null "http://127.0.0.1:$PORT/api/health/live" 2>/dev/null; do
    n=$((n + 1)); [ "$n" -le 180 ] || { echo "[railway] server never came up, admin not created" >&2; exit 1; }
    sleep 2
  done
  for try in 1 2 3 4 5; do
    code=$(curl -s -o /dev/null -w '%{http_code}' -H 'content-type: application/json' -d "$BODY" "http://127.0.0.1:$PORT/api/auth/setup")
    case "$code" in
      200) echo "[railway] created workspace and admin $ADMIN_EMAIL"; exit 0;;
      403) echo "[railway] workspace already exists, admin left unchanged"; exit 0;;
    esac
    echo "[railway] setup answered $code (try $try)" >&2; sleep 5
  done
  echo "[railway] admin not created" >&2
) &

if [ "$(id -u)" = 0 ]; then
  exec setpriv --reuid=1000 --regid=1000 --clear-groups "$@"
fi
exec "$@"
