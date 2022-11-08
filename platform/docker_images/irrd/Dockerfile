FROM alpine

RUN apk update \
    && apk add g++ python3-dev postgresql-dev py3-pip linux-headers bash \
    && pip3 install irrd --ignore-installed six

EXPOSE 43
EXPOSE 8000

RUN adduser -D irrd
COPY irrd.yaml /etc/irrd.yaml
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN mkdir /var/log/irrd
RUN touch /var/log/irrd/irrd.log 
RUN chown --recursive irrd:irrd /var/log/irrd

ENTRYPOINT ["docker-entrypoint.sh"]
