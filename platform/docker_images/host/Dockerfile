FROM d_base:latest

# Install cpanminus for bgpsimple
# cpanminus and build-essential needed for this
# RUN cpanm Net::BGP

RUN apk add --no-cache openssh-server \
    && ssh-keygen -A \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config \
    && sed -i 's/#PrintMotd yes/PrintMotd no/g' /etc/ssh/sshd_config \
    # Unlocks the root user so that ssh login is allowed.
    && sed -i s/root:!/"root:*"/g /etc/shadow \
    && mkdir -p /var/run/sshd /root/.ssh \
    && chmod 0755 /var/run/sshd

EXPOSE 22

CMD ["/usr/sbin/sshd", "-D", "-e"]
