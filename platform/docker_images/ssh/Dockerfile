FROM debian:stretch
RUN apt-get update && apt-get install -y rsyslog vim locales iputils-ping \
	openssh-server less zip tmux screen

# Set locale
RUN sed -i -e 's/# \(en_US\.UTF-8 .*\)/\1/' /etc/locale.gen && \
    locale-gen
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Add startup script and set it as entrypoint
ADD docker-start /usr/sbin/docker-start
ADD goto_completion /root/.goto_completion
RUN echo "source ~/.goto_completion" >> /root/.bashrc
# Warn students trying to run ssh-keygen on the ssh host, they have misunderstood where to run it
RUN echo alias ssh-keygen=\"echo You should not be running ssh-keygen on the proxy host. Instead, run ssh-keygen on your remote machine, e.g. the lab machine. Then run ssh-copy-id on your remote machine to authorize your key on the proxy host.\" >> ~/.bashrc
RUN chmod +x /usr/sbin/docker-start
ENTRYPOINT ["/usr/sbin/docker-start"]
