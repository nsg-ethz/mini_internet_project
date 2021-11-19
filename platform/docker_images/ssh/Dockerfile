FROM d_base:latest

# Install cpanminus for bgpsimple
# cpanminus and build-essential needed for this
# RUN cpanm Net::BGP

RUN apk add --no-cache openssh-client openssh-server \
    && ssh-keygen -A \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/g' /etc/ssh/sshd_config \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/g' /etc/ssh/sshd_config \
    && sed -i 's/AllowTcpForwarding no/AllowTcpForwarding yes/g' /etc/ssh/sshd_config \
    && sed -i 's/GatewayPorts no/GatewayPorts yes/g' /etc/ssh/sshd_config \
    && mkdir -p /var/run/sshd /root/.ssh \
    && chmod 0755 /var/run/sshd

EXPOSE 22/tcp

CMD ["/usr/sbin/sshd", "-D", "-e"]
