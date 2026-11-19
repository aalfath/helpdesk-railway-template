# Frappe Helpdesk scheduler: `bench schedule` puts due jobs (SLA timers, email pulls, auto-close)
# on the Redis queue; the workers in the Helpdesk service run them. Stateless.
FROM ghcr.io/frappe/helpdesk:v16.2.0@sha256:7279a0c2e54f07480776d22bfd9a3426f859f7334d797a999e37dbe43333febd

COPY --chmod=755 start.sh /usr/local/bin/railway-start.sh
ENV SITE_NAME=helpdesk.local \
    DB_NAME=helpdesk \
    DB_PORT=3306
ENTRYPOINT ["/usr/local/bin/railway-start.sh"]
CMD []
