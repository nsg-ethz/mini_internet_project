FROM d_base:latest

# Install and configure supervisor
RUN apk add --no-cache supervisor gawk tzdata \
    && mkdir -p /var/log/supervisor

COPY supervisord.conf /etc/supervisor/supervisord.conf
COPY stop-supervisord.sh /usr/local/bin/stop-supervisord
COPY logger.sh /usr/local/bin/tail-supervisor-logs
RUN chmod +x /usr/local/bin/stop-supervisord /usr/local/bin/tail-supervisor-logs

ENV TZ="Europe/Paris"

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]
