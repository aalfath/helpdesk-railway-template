#!/bin/bash
# Frappe Helpdesk scheduler service for Railway.
# Writes the bench and site config it needs from service variables (no volume), waits until the
# Helpdesk service has created the site's database, then runs `bench schedule`.
set -euo pipefail
cd /home/frappe/frappe-bench
: "${DB_HOST:?DB_HOST is required}"
: "${DB_PASSWORD:?DB_PASSWORD is required}"
: "${REDIS_CACHE_URL:?REDIS_CACHE_URL is required}"
: "${REDIS_QUEUE_URL:?REDIS_QUEUE_URL is required}"
SITE="${SITE_NAME:-helpdesk.local}"
mkdir -p "sites/$SITE" config
env/bin/python - "$SITE" <<'PY'
import json, os, sys
site = sys.argv[1]
json.dump({
    "db_host": os.environ["DB_HOST"],
    "db_port": int(os.environ.get("DB_PORT", "3306")),
    "redis_cache": os.environ["REDIS_CACHE_URL"],
    "redis_queue": os.environ["REDIS_QUEUE_URL"],
    "redis_socketio": os.environ["REDIS_QUEUE_URL"],
    "default_site": site,
}, open("sites/common_site_config.json", "w"), indent=1)
db = os.environ.get("DB_NAME", "helpdesk")
json.dump({"db_name": db, "db_user": db, "db_password": os.environ["DB_PASSWORD"], "db_type": "mariadb"},
          open(f"sites/{site}/site_config.json", "w"), indent=1)
PY
echo "[helpdesk-railway] waiting for the Helpdesk site database"
until env/bin/python - <<'PY'
import os, sys, pymysql
try:
    c = pymysql.connect(host=os.environ["DB_HOST"], port=int(os.environ.get("DB_PORT", "3306")),
                        user=os.environ.get("DB_NAME", "helpdesk"), password=os.environ["DB_PASSWORD"],
                        database=os.environ.get("DB_NAME", "helpdesk"), connect_timeout=5)
    cur = c.cursor()
    cur.execute("SELECT COUNT(*) FROM `tabInstalled Application` WHERE app_name='helpdesk'")
    sys.exit(0 if cur.fetchone()[0] else 1)
except Exception:
    sys.exit(1)
PY
do sleep 10; done
echo "[helpdesk-railway] site is ready, starting the scheduler"
exec bench schedule
