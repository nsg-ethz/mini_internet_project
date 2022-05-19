FROM d_base:latest

RUN apk add --no-cache bind \
    && mkdir -p /var/cache/bind

EXPOSE 53

COPY named.conf /etc/bind/named.conf
# Add startup script and set it as entrypoint
COPY docker-start /docker-start
RUN chmod +x /docker-start
ENTRYPOINT ["/docker-start"]
CMD ["/usr/sbin/named", "-c", "/etc/bind/named.conf", "-f", "-u", "named"]
