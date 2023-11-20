FROM debian:stretch
RUN apt-get update && apt-get install -y locales rsyslog iputils-ping openssh-server traceroute nmap dnsutils

# Set locale
RUN sed -i -e 's/# \(en_US\.UTF-8 .*\)/\1/' /etc/locale.gen && \
    locale-gen
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Add startup script and set it as entrypoint
ADD docker-start /docker-start
RUN chmod +x /docker-start
ADD launch_traceroute.sh /launch_traceroute.sh
RUN chmod +x /launch_traceroute.sh
ENTRYPOINT ["/docker-start"]