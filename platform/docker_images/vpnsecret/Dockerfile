FROM python:3-alpine

# Basic debugging tools.
RUN apk add --no-cache tini bash bash-completion util-linux coreutils libqrencode-tools \
                       binutils findutils grep vim nano tzdata \
                       iputils net-tools bind-tools tcptraceroute tcpdump

RUN apk add --no-cache openssh-server \
    && ssh-keygen -A \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config \
    && sed -i 's/#PrintMotd yes/PrintMotd no/g' /etc/ssh/sshd_config \
    # Unlocks the root user so that ssh login is allowed.
    && sed -i s/root:!/"root:*"/g /etc/shadow \
    && mkdir -p /var/run/sshd /root/.ssh \
    && chmod 0755 /var/run/sshd

RUN pip install flask
# Install bjoern and dependencies for install
RUN apk add --no-cache --virtual .deps \
    musl-dev gcc git && \
    # Keep libev for running bjoern, libjpeg and zlib for Pillow
    apk add --no-cache libev-dev zlib-dev jpeg-dev && \
    pip install bjoern

COPY supervisord.conf /etc/supervisor/conf.d/processes.conf
CMD ["python3", "/server/vpnsecret.py"]
