FROM d_base:latest

# Install cpanminus for bgpsimple
# cpanminus and build-essential needed for this
# RUN cpanm Net::BGP

RUN apk add --no-cache openssh-client openssh-server zip ncurses \
    && ssh-keygen -A \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/g' /etc/ssh/sshd_config \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/g' /etc/ssh/sshd_config \
    && sed -i 's/AllowTcpForwarding no/AllowTcpForwarding yes/g' /etc/ssh/sshd_config \
    && sed -i 's/GatewayPorts no/GatewayPorts yes/g' /etc/ssh/sshd_config \
    && sed -i 's@AuthorizedKeysFile	.ssh/authorized_keys@AuthorizedKeysFile /etc/ssh/authorized_keys .ssh/authorized_keys@g' /etc/ssh/sshd_config \
    && mkdir -p /var/run/sshd /root/.ssh \
    && chmod 0755 /var/run/sshd

ADD goto_completion /root/.goto_completion
RUN echo "source ~/.goto_completion" >> /root/.bashrc
RUN echo "source ~/.bashrc" > /root/.profile
# Warn students trying to run ssh-keygen on the ssh host, they have misunderstood where to run it
RUN echo alias ssh-keygen=\"echo You should not be running ssh-keygen on the proxy host. Instead, run ssh-keygen on your remote machine, e.g. the lab machine. Then run ssh-copy-id on your remote machine to authorize your key on the proxy host.\" >> ~/.bashrc

EXPOSE 22/tcp

CMD ["/usr/sbin/sshd", "-D", "-e"]


