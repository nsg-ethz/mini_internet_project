FROM p4lang/third-party:stable
LABEL maintainer="Antonin Bas <antonin@barefootnetworks.com>"
LABEL description="This Docker image does not have any dependency on PI or P4 \
Runtime, it only builds bmv2 simple_switch."

# Default to using 2 make jobs, which is a good default for CI. If you're
# building locally or you know there are more cores available, you may want to
# override this.

RUN apt-get update && apt-get install -y git \
    rsyslog \
    locales \
    iputils-ping \
    inetutils-traceroute \
    openssh-server \
    vim \
    tcpdump \
    net-tools \
    dnsutils \
    build-essential \
    iperf3 \
    ethtool
    
# Set locale
RUN sed -i -e 's/# \(en_US\.UTF-8 .*\)/\1/' /etc/locale.gen && \
  locale-gen
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

ARG MAKEFLAGS=-j2

ENV BM_DEPS automake \
            curl \
            git \
            libjudy-dev \
            libgmp-dev \
            libpcap-dev \
            libboost-dev \
            libboost-program-options-dev \
            libboost-system-dev \
            libboost-filesystem-dev \
            libboost-thread-dev \
            libtool
ENV BM_RUNTIME_DEPS libboost-program-options1.58.0 \
                    libboost-system1.58.0 \
                    libboost-filesystem1.58.0 \
                    libboost-thread1.58.0 \
                    libgmp10 libjudydebian1 \
                    libpcap0.8 \
                    python

RUN git clone --branch 1.14.0 https://github.com/p4lang/behavioral-model

WORKDIR /behavioral-model/
RUN apt-get update && \
    apt-get install -y --no-install-recommends software-properties-common && \
    apt-get install -y autoconf autogen && \
    add-apt-repository -y ppa:ubuntu-toolchain-r/test && \
    apt-get update && \
    apt-get install -y --no-install-recommends $BM_DEPS $BM_RUNTIME_DEPS && \
    ./autogen.sh && \
    ./configure --without-nanomsg --disable-elogger --disable-logging-macros 'CFLAGS=-g -O2' 'CXXFLAGS=-g -O2' && \
    make && \
    make install-strip && \
    ldconfig && \
    make clean
    #apt-get purge -y $BM_DEPS && \
    #apt-get autoremove --purge -y && \
    #rm -rf /var/cache/apt/* /var/lib/apt/lists/*
    #rm -rf /behavioral-model /var/cache/apt/* /var/lib/apt/lists/*

RUN apt-get purge -y $BM_DEPS && \
    apt-get autoremove --purge -y && \
    rm -rf /var/cache/apt/* /var/lib/apt/lists/*
WORKDIR /

#COPY nanomsg_client.py /home/nanomsg_client.py
COPY docker-start /usr/sbin/docker-start
RUN chmod +x /usr/sbin/docker-start
ENTRYPOINT ["/usr/sbin/docker-start"]
