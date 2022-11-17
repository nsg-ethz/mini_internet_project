FROM d_base_supervisor:latest

RUN apk add --no-cache g++ python3-dev postgresql-dev py3-pip linux-headers bash\
    && pip3 install --no-cache-dir irrd --ignore-installed six

RUN apk add --no-cache openssh-server \
    && ssh-keygen -A \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config \
    && sed -i 's/#PrintMotd yes/PrintMotd no/g' /etc/ssh/sshd_config \
    # Unlocks the root user so that ssh login is allowed.
    && sed -i s/root:!/"root:*"/g /etc/shadow \
    && mkdir -p /var/run/sshd /root/.ssh \
    && chmod 0755 /var/run/sshd

EXPOSE 22

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8
ENV TZ="Europe/Paris"

EXPOSE 43
EXPOSE 8080

RUN adduser -D irrd
COPY irrd.yaml /etc/irrd.yaml
COPY supervisord.conf /etc/supervisor/conf.d/processes.conf

RUN rm /etc/supervisord.conf
RUN mkdir /var/log/irrd
RUN touch /var/log/irrd/irrd.log 
RUN chown --recursive irrd:irrd /var/log/irrd
