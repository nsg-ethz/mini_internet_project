FROM python:3-alpine

RUN apk add --no-cache tini bash bash-completion util-linux coreutils \
                       binutils findutils grep vim nano tzdata \
                       iputils net-tools bind-tools tcptraceroute tcpdump

# Install bjoern and dependencies for install
RUN apk add --no-cache --virtual .deps \
    musl-dev gcc git && \
    # Keep libev for running bjoern, libjpeg and zlib for Pillow
    apk add --no-cache libev-dev zlib-dev jpeg-dev && \
    pip install bjoern

ENV TZ="Europe/Paris"

COPY server /server
RUN pip install -e /server

CMD ["python3", "/server/run.py"]
