FROM debian:stretch
RUN apt-get update && apt-get install -y rsyslog locales iputils-ping openssh-server nmap net-tools tmux vim

# Set locale
RUN sed -i -e 's/# \(en_US\.UTF-8 .*\)/\1/' /etc/locale.gen && \
    locale-gen
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Add startup script and set it as entrypoint
ADD ping.py /home/ping.py
RUN chmod +x /home/ping.py
ADD docker-start /docker-start
RUN chmod +x /docker-start
ENTRYPOINT ["/docker-start"]
