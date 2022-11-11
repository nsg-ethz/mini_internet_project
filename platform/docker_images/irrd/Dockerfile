FROM alpine:3.16

RUN apk add --no-cache g++ python3-dev postgresql-dev py3-pip linux-headers bash\
    && pip3 install --no-cache-dir irrd --ignore-installed six

RUN apk add --no-cache tini bash bash-completion util-linux coreutils \
                       binutils findutils grep vim nano tzdata \
                       iputils net-tools bind-tools iperf3 tcptraceroute tcpdump nmap nmap-nping \
    && echo "export PS1=\"\[\033[38;5;2m\]\u@\h \[\033[38;5;75m\]\w\e[m> \"" > /root/.bashrc \
    && sed -i -e "s/bin\/ash/bin\/bash/" /etc/passwd

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8
ENV TZ="Europe/Paris"

EXPOSE 43
EXPOSE 8000

RUN adduser -D irrd
COPY irrd.yaml /etc/irrd.yaml
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN mkdir /var/log/irrd
RUN touch /var/log/irrd/irrd.log 
RUN chown --recursive irrd:irrd /var/log/irrd

ENTRYPOINT ["docker-entrypoint.sh"]
