FROM debian:stretch

# Install dependencies
RUN apt-get update && apt-get install -y rsyslog locales libpcre3-dev apt-transport-https ca-certificates curl wget logrotate \
    libc-ares2 libjson-c3 vim systemd procps openssh-server inetutils-traceroute net-tools tcpdump dnsutils vlan gnupg lsb-release

# Install FRR
## add FRR GPG key
COPY frr_keys.asc /frr_keys.asc
RUN apt-key add /frr_keys.asc

## possible values for FRRVER: frr-6 frr-7 frr-stable
## frr-stable will be the latest official stable release
ENV FRRVER="frr-stable"
RUN echo deb https://deb.frrouting.org/frr $(lsb_release -s -c) $FRRVER | tee -a /etc/apt/sources.list.d/frr.list
RUN apt-get update && apt-get install -y frr frr-pythontools

# Set locale
RUN sed -i -e 's/# \(en_US\.UTF-8 .*\)/\1/' /etc/locale.gen && \
    locale-gen
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Add startup script and set it as entrypoint
COPY docker-start /usr/sbin/docker-start
COPY looking_glass.sh /home/.looking_glass.sh

RUN mkdir -p /root/.ssh
RUN chmod +x /usr/sbin/docker-start
ENTRYPOINT ["/usr/sbin/docker-start"]
