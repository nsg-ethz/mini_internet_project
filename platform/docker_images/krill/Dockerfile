# -- stage 1: build static krill with musl libc for alpine
FROM d_base:latest as build

# Specify what version of krill should be built.
ARG KRILL_VERSION=0.9.0-rc2

RUN apk add wget openssl-dev patch rust cargo

WORKDIR /tmp/krill

COPY krill_cli.patch /

RUN wget "https://github.com/NLnetLabs/krill/archive/refs/tags/v${KRILL_VERSION}.tar.gz" -O - | tar -xz --strip-components=1
RUN patch -p1 < /krill_cli.patch
RUN cargo build \
    --target x86_64-alpine-linux-musl \
    --features multi-user \
    --release \
    --locked

# -- stage 2: create image with the static krill executable
FROM d_base_supervisor:latest
COPY --from=build /tmp/krill/target/x86_64-alpine-linux-musl/release/krill /usr/local/bin/
COPY --from=build /tmp/krill/target/x86_64-alpine-linux-musl/release/krillc /usr/local/bin/
COPY --from=build /tmp/krill/target/x86_64-alpine-linux-musl/release/krillpubd /usr/local/bin/
COPY --from=build /tmp/krill/target/x86_64-alpine-linux-musl/release/krillpubc /usr/local/bin/

RUN apk add --no-cache haproxy curl rsync libgcc ca-certificates openssl openssh-server \
    && ssh-keygen -A \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config \
    && sed -i 's/#PrintMotd yes/PrintMotd no/g' /etc/ssh/sshd_config \
    # Unlocks the root user so that ssh login is allowed.
    && sed -i s/root:!/"root:*"/g /etc/shadow \
    && mkdir -p /var/run/sshd /root/.ssh \
    && chmod 0755 /var/run/sshd \
    && mkdir -p /var/krill/data/ssl

RUN apk add iproute2-minimal iptables

COPY haproxy.cfg /etc/haproxy/haproxy.cfg
COPY supervisord.conf /etc/supervisor/conf.d/processes.conf

COPY docker-start /docker-start
RUN chmod +x /docker-start

ENTRYPOINT [ "/docker-start" ]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]
