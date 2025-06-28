FROM python:3-alpine

# Basic debugging tools.
RUN apk add --no-cache tini bash bash-completion util-linux coreutils libqrencode-tools \
                       binutils findutils grep vim nano tzdata \
                       iputils net-tools bind-tools tcptraceroute tcpdump 

# Add Docker CLI
RUN apk add --no-cache docker-cli

# Install bjoern and dependencies for install
RUN apk add --no-cache --virtual .deps \
    musl-dev gcc git && \
    # Keep libev for running bjoern, libjpeg and zlib for Pillow
    apk add --no-cache libev-dev zlib-dev jpeg-dev && \
    pip install bjoern && \
    pip install jc

COPY server /server
RUN pip install -e /server

# Default config dir
ENV SERVER_CONFIG="/server/config.py"


CMD ["python3", "/server/run.py"]
