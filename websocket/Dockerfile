# Frappe Helpdesk realtime service: Frappe's socket.io server (node apps/frappe/socketio.js).
# Stateless; reached only by the Helpdesk service's nginx over Railway's private network.
FROM ghcr.io/frappe/helpdesk:v16.2.0@sha256:7279a0c2e54f07480776d22bfd9a3426f859f7334d797a999e37dbe43333febd

COPY --chmod=755 start.sh /usr/local/bin/railway-start.sh
ENV SOCKETIO_PORT=9000 \
    HELPDESK_PORT=8080
ENTRYPOINT ["/usr/local/bin/railway-start.sh"]
CMD []
