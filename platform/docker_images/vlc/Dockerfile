FROM debian:stretch
RUN apt-get update && apt-get install -y rsyslog locales iputils-ping traceroute \
        openssh-server vim tcpdump net-tools dnsutils iperf3 build-essential smcroute vlc git \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config \
    && mkdir -p /var/run/sshd \
    && chmod 0755 /var/run/sshd \
    && mkdir -p /root/.ssh

# Set locale
RUN sed -i -e 's/# \(en_US\.UTF-8 .*\)/\1/' /etc/locale.gen && \
  locale-gen
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

RUN git clone https://github.com/troglobit/mtools.git

EXPOSE 22/tcp

CMD ["/usr/sbin/sshd", "-D", "-e"]
