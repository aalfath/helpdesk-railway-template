# Frappe Helpdesk web service: nginx (public PORT) + gunicorn + background workers.
# Owns the `sites` volume, creates the site on first start and migrates it after an update.
FROM ghcr.io/frappe/helpdesk:v16.2.0@sha256:7279a0c2e54f07480776d22bfd9a3426f859f7334d797a999e37dbe43333febd

USER root
# Keep a copy of the bench files that the volume hides (apps.txt, apps.json).
RUN cp -a /home/frappe/frappe-bench/sites /home/frappe/sites-image
COPY --chmod=755 start.sh /usr/local/bin/railway-start.sh
COPY nginx.conf.template /templates/nginx/railway.conf.template

ENV SITE_NAME=helpdesk.local \
    DB_PORT=3306 \
    PORT=8080
# Starts as root only to fix the volume's ownership, then runs everything as `frappe`.
ENTRYPOINT ["/usr/local/bin/railway-start.sh"]
CMD []
