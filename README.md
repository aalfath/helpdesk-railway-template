[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/helpdesk-1?utm_medium=integration&utm_source=button&utm_campaign=helpdesk)

# Frappe Helpdesk on Railway

One-click [Frappe Helpdesk](https://frappe.io/helpdesk) (open-source customer support ticketing, a Zendesk alternative) on Railway, as the full multi-service stack that upstream's [frappe_docker](https://github.com/frappe/frappe_docker) runs.

**Version:** Helpdesk **v16.2.0** on Frappe **v16.60.2**, from the official image `ghcr.io/frappe/helpdesk:v16.2.0@sha256:7279a0c2e54f07480776d22bfd9a3426f859f7334d797a999e37dbe43333febd` (it includes the required Telephony app).

## Services

| Service | Built from | What it does | Volume |
|---|---|---|---|
| **Helpdesk** (public) | `helpdesk/` | nginx on `PORT`, gunicorn (Frappe backend) and the background workers. Creates the site on first start, runs `bench migrate` after an update | `/home/frappe/frappe-bench/sites` (site config, attachments, backups) |
| **Websocket** | `websocket/` | Frappe's socket.io server for live ticket updates; nginx forwards `/socket.io` to it over the private network | none |
| **Scheduler** | `scheduler/` | `bench schedule`: puts due jobs (SLA timers, email pulls, auto-close) on the queue | none |
| **MariaDB** | `mariadb:11.8.9` (pinned digest) | Database | `/var/lib/mysql` |
| **Redis-Cache** | `redis:8.2.6` (pinned digest) | Cache, in memory only (LRU, 256 MB) | none |
| **Redis-Queue** | `redis:8.2.6` (pinned digest) | Job queue and realtime events (append-only file) | `/data` |

The background workers run inside the Helpdesk service because they write attachments and backups into the `sites` folder, and a Railway volume attaches to one service only. Raise `BACKGROUND_WORKERS` on the Helpdesk service for more worker processes.

## Variables

All are filled in by the template; the deploy form asks for nothing.

- `ADMIN_PASSWORD` (Helpdesk): generated password of the `Administrator` user. Read it in the Helpdesk service's Variables tab. It is used once, when the site is created; change the password in Helpdesk afterwards.
- `DB_PASSWORD` (Helpdesk, referenced by Scheduler): generated password of the site's own MariaDB user.
- `MARIADB_ROOT_PASSWORD` (MariaDB) and `REDIS_PASSWORD` (both Redis services): generated.
- References wire the rest: `DB_HOST`, `DB_ROOT_PASSWORD`, `REDIS_CACHE_URL`, `REDIS_QUEUE_URL`, `SOCKETIO_UPSTREAM`, `HELPDESK_HOST`.
- Optional, not set by default: `GUNICORN_WORKERS` (2), `GUNICORN_THREADS` (4), `BACKGROUND_WORKERS` (1), `CLIENT_MAX_BODY_SIZE` (`50m`).

## After deploy

1. Wait for the Helpdesk service to finish its first start (about 2 to 4 minutes; a "Helpdesk is starting" page shows meanwhile).
2. Open the public URL, sign in as `Administrator` with `ADMIN_PASSWORD`, and go through the setup at `/helpdesk`.
3. Add an email account (Helpdesk → Admin settings → Email accounts) so customers can open tickets by email, and invite agents. SMTP is not included.

## Updates

Every service builds from this repo. When a new Helpdesk release comes out, we bump the pinned image in all three Dockerfiles on `main` and note it in [CHANGELOG.md](CHANGELOG.md); Railway then shows "update available" on your project. Read the changelog, back up first (MariaDB plus the Helpdesk `sites` volume), then apply the update. The Helpdesk service runs `bench migrate` by itself when the app versions change, and serves the holding page while it runs.

## Layout

- `helpdesk/`: `Dockerfile`, `start.sh` (volume ownership, bench config from variables, site creation or migrate, process supervisor), `nginx.conf.template`.
- `websocket/`: `Dockerfile`, `start.sh`.
- `scheduler/`: `Dockerfile`, `start.sh` (waits until the site's database exists).

Licence of this wrapper: MIT. Frappe Helpdesk itself is AGPL-3.0.
