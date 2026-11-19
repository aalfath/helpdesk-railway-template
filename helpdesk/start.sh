#!/bin/bash
# Frappe Helpdesk web service for Railway (https://github.com/aalfath/helpdesk-railway-template).
# Runs nginx (public PORT), gunicorn and the background workers, which all need the `sites`
# volume. The socket.io server and the scheduler run as their own Railway services.
set -euo pipefail

BENCH=/home/frappe/frappe-bench
SITE="${SITE_NAME:-helpdesk.local}"
DB_NAME="${DB_NAME:-helpdesk}"
export PORT="${PORT:-8080}"

# 1. As root: make the volume writable for the frappe user, then drop privileges.
if [ "$(id -u)" = "0" ]; then
  rm -rf "$BENCH/sites/lost+found"
  if [ "$(stat -c %u "$BENCH/sites")" != "1000" ]; then chown -R frappe:root "$BENCH/sites"; fi
  chown -R frappe:root "$BENCH/logs" 2>/dev/null || true
  exec runuser -u frappe -- bash "$0" "$@"
fi

cd "$BENCH"
umask 0002
# Re-open stdout/stderr as pipes owned by frappe (the inherited ones belong to root).
exec > >(cat) 2> >(cat >&2)
log() { echo "[helpdesk-railway] $*"; }

: "${DB_HOST:?DB_HOST is required}"
: "${DB_ROOT_PASSWORD:?DB_ROOT_PASSWORD is required}"
: "${DB_PASSWORD:?DB_PASSWORD is required}"
: "${REDIS_CACHE_URL:?REDIS_CACHE_URL is required}"
: "${REDIS_QUEUE_URL:?REDIS_QUEUE_URL is required}"
: "${SOCKETIO_UPSTREAM:?SOCKETIO_UPSTREAM is required (host:port of the Websocket service)}"
DB_PORT="${DB_PORT:-3306}"

# 2. Bench files that the volume hides: refresh them from the image on every start.
cp -f /home/frappe/sites-image/apps.txt /home/frappe/sites-image/apps.json sites/
rm -rf sites/assets && ln -s "$BENCH/assets" sites/assets
[ -f sites/common_site_config.json ] || echo '{}' > sites/common_site_config.json

# 3. Shared bench config from the service variables (Railway references).
env/bin/python - <<'PY'
import json, os
p = "sites/common_site_config.json"
c = json.load(open(p))
c.update({
    "db_host": os.environ["DB_HOST"],
    "db_port": int(os.environ.get("DB_PORT", "3306")),
    "redis_cache": os.environ["REDIS_CACHE_URL"],
    "redis_queue": os.environ["REDIS_QUEUE_URL"],
    "redis_socketio": os.environ["REDIS_QUEUE_URL"],
    "socketio_port": 9000,
})
json.dump(c, open(p, "w"), indent=1, sort_keys=True)
PY

wait_for() { # url-or-host port name
  local i
  for i in $(seq 1 120); do
    if env/bin/python -c "import socket,sys; socket.create_connection((sys.argv[1], int(sys.argv[2])), 3)" "$1" "$2" 2>/dev/null; then
      log "$3 is reachable"; return 0
    fi
    sleep 2
  done
  log "$3 at $1:$2 not reachable"; exit 1
}
hostport() { local h="${1#*://}"; h="${h##*@}"; echo "${h%%/*}"; }
wait_for "$DB_HOST" "$DB_PORT" MariaDB
q="$(hostport "$REDIS_QUEUE_URL")"; wait_for "${q%:*}" "${q##*:}" Redis-Queue
c="$(hostport "$REDIS_CACHE_URL")"; wait_for "${c%:*}" "${c##*:}" Redis-Cache

# While the site is created or migrated (minutes), serve a holding page on PORT so Railway's
# health check passes and visitors see what is happening.
SETUP_PID=""
setup_page_start() {
  [ -n "$SETUP_PID" ] && return 0
  cat > /tmp/nginx-setup.conf <<NGINX
worker_processes 1;
pid /tmp/nginx-setup.pid;
error_log stderr;
events { worker_connections 64; }
http {
  access_log off;
  client_body_temp_path /tmp/nginx-body;
  proxy_temp_path /tmp/nginx-proxy;
  fastcgi_temp_path /tmp/nginx-fastcgi;
  uwsgi_temp_path /tmp/nginx-uwsgi;
  scgi_temp_path /tmp/nginx-scgi;
  server {
    listen $PORT;
    listen [::]:$PORT;
    location = /api/method/ping { default_type application/json; return 200 '{"message":"pong"}'; }
    location / {
      default_type text/html;
      add_header Retry-After 30 always;
      return 503 '<!doctype html><meta http-equiv="refresh" content="20"><title>Helpdesk is starting</title><p style="font-family:sans-serif;margin:3em">Helpdesk is being set up (first start or update). This takes a few minutes; the page reloads by itself.</p>';
    }
  }
}
NGINX
  nginx -e stderr -c /tmp/nginx-setup.conf -g 'daemon off;' & SETUP_PID=$!
}
setup_page_stop() {
  [ -z "$SETUP_PID" ] && return 0
  kill -TERM "$SETUP_PID" 2>/dev/null; wait "$SETUP_PID" 2>/dev/null || true; SETUP_PID=""
}

# 4. Create the site on first start; migrate when the app versions in the image change.
VERSION="$(for a in $(cat sites/apps.txt); do printf '%s=%s ' "$a" "$(sed -n 's/^__version__ = "\(.*\)"/\1/p' "apps/$a/$a/__init__.py")"; done)"
if [ ! -f "sites/$SITE/.railway-installed" ]; then
  : "${ADMIN_PASSWORD:?ADMIN_PASSWORD is required for the first start}"
  log "Creating site $SITE with Helpdesk (first start, takes a few minutes)"
  setup_page_start
  bench new-site "$SITE" --force \
    --mariadb-user-host-login-scope='%' \
    --db-root-username root --db-root-password "$DB_ROOT_PASSWORD" \
    --db-name "$DB_NAME" --db-password "$DB_PASSWORD" \
    --admin-password "$ADMIN_PASSWORD" \
    --install-app helpdesk --set-default
  bench --site "$SITE" scheduler enable
  # Scheduled job types are stamped in the install timezone (Asia/Kolkata); backdate them so a
  # site timezone west of that doesn't push every job's first run hours into the future.
  bench --site "$SITE" mariadb -e "UPDATE \`tabScheduled Job Type\` SET creation='2000-01-01' WHERE name > '' AND last_execution IS NULL"
  echo "$VERSION" > "sites/$SITE/.railway-version"
  touch "sites/$SITE/.railway-installed"
  log "Site created"
elif [ "$(cat "sites/$SITE/.railway-version" 2>/dev/null)" != "$VERSION" ]; then
  log "App versions changed to: $VERSION; running bench migrate"
  setup_page_start
  bench --site "$SITE" migrate
  echo "$VERSION" > "sites/$SITE/.railway-version"
fi
bench use "$SITE" >/dev/null
if [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
  bench --site "$SITE" set-config host_name "https://$RAILWAY_PUBLIC_DOMAIN" >/dev/null
fi

# 5. nginx config. Railway's private DNS server is the container's resolver.
ns="$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf)"
case "$ns" in *:*) ns="[$ns]";; esac
export NGINX_RESOLVER="${ns:-127.0.0.11}" SITE_NAME="$SITE" \
  NGINX_WORKERS="${NGINX_WORKERS:-2}" CLIENT_MAX_BODY_SIZE="${CLIENT_MAX_BODY_SIZE:-50m}"
# shellcheck disable=SC2016
envsubst '${PORT} ${NGINX_RESOLVER} ${NGINX_WORKERS} ${SITE_NAME} ${SOCKETIO_UPSTREAM} ${CLIENT_MAX_BODY_SIZE}' \
  < /templates/nginx/railway.conf.template > /tmp/nginx.conf
nginx -e stderr -t -c /tmp/nginx.conf

setup_page_stop

# 6. Run every process; if one exits, stop the rest so Railway restarts the container.
pids=()
start() { log "starting $1"; shift; "$@" & pids+=($!); }
trap 'kill -TERM "${pids[@]}" 2>/dev/null; wait "${pids[@]}"; exit 0' TERM INT
start gunicorn env/bin/gunicorn --chdir="$BENCH/sites" --bind=127.0.0.1:8000 \
  --threads="${GUNICORN_THREADS:-4}" --workers="${GUNICORN_WORKERS:-2}" --worker-class=gthread \
  --worker-tmp-dir=/dev/shm --timeout=120 --preload frappe.app:application
for i in $(seq 1 "${BACKGROUND_WORKERS:-1}"); do
  start "worker-$i" bench worker --queue long,default,short
done
start nginx nginx -e stderr -c /tmp/nginx.conf -g 'daemon off;'
set +e
wait -n "${pids[@]}"
code=$?
log "a process exited with code $code, stopping the container"
kill -TERM "${pids[@]}" 2>/dev/null
wait "${pids[@]}"
exit 1
