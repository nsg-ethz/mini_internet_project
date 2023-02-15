FROM alpine:latest AS builder

RUN apk upgrade && apk add git autoconf automake file gcc gzip libtool make musl-dev

WORKDIR /root
RUN git clone https://github.com/bgp/bgpq4.git

WORKDIR /root/bgpq4

RUN ./bootstrap
RUN ./configure
RUN make

FROM d_base:latest

# Install cpanminus for bgpsimple
# cpanminus and build-essential needed for this
# RUN cpanm Net::BGP

RUN apk add --no-cache openssh-server curl \
    && ssh-keygen -A \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config \
    && sed -i 's/#PrintMotd yes/PrintMotd no/g' /etc/ssh/sshd_config \
    # Unlocks the root user so that ssh login is allowed.
    && sed -i s/root:!/"root:*"/g /etc/shadow \
    && mkdir -p /var/run/sshd /root/.ssh \
    && chmod 0755 /var/run/sshd

COPY --from=builder /root/bgpq4/bgpq4 /usr/local/bin/bgpq4

EXPOSE 22

CMD ["/usr/sbin/sshd", "-D", "-e"]
