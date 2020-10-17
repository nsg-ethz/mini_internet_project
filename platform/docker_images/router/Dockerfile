FROM debian:stretch

# Install dependencies
RUN apt-get update
RUN apt-get install -y \
    build-essential \
    git \
    rsyslog \
    locales \
    libpcre3-dev \
    libpcre3-dev \
    apt-transport-https \
    ca-certificates \
    curl \
    wget \
    logrotate \
    libc-ares2 \
    libjson-c3 \
    vim \
    systemd \
    procps \
    openssh-server \
    inetutils-traceroute \
    net-tools \
    tcpdump \
    dnsutils \
    vlan \
    gnupg \
    lsb-release \
    autogen \
    python2.7 \
    cmake \
    libpcre3 \
    libpcre3-dev \
    autoconf \
    automake \
    libtool \
    make \
    libreadline-dev \
    texinfo \
    libjson-c-dev \
    pkg-config \
    bison \
    flex \
    libc-ares-dev \
    python3-dev \
    python3-pytest \
    python3-sphinx \
    libsnmp-dev \
    libsystemd-dev \
    libcap-dev

RUN mkdir /libyang
# We need the devel branch for the VRF otherwise we get an error when into an interface configuration
RUN git clone -b devel https://github.com/CESNET/libyang.git /libyang
RUN mkdir /libyang/build

# Install FRR
## add FRR GPG key
COPY frr_keys.asc /frr_keys.asc
RUN apt-key add /frr_keys.asc

RUN addgroup --system --gid 92 frr
RUN addgroup --system --gid 85 frrvty
RUN adduser --system --ingroup frr --home /var/opt/frr/ --gecos "FRR suite" --shell /bin/false frr
RUN usermod -a -G frrvty frr

RUN mkdir /frr
RUN git clone --depth 1 --branch frr-7.2.1 https://github.com/FRRouting/frr.git /frr
#RUN git clone --branch frr-7.4 https://github.com/FRRouting/frr.git /frr
#RUN git clone --branch frr-7.3.1 https://github.com/FRRouting/frr.git /frr
RUN ldconfig
WORKDIR /frr
RUN ./bootstrap.sh

## For some reasons we need to install libyang here and not around line 50 otherwise the configure fails.
WORKDIR /libyang/build
RUN cmake -DENABLE_LYD_PRIV=ON -DCMAKE_INSTALL_PREFIX:PATH=/usr -D CMAKE_BUILD_TYPE:String="Release" ..
RUN make
RUN make install
RUN ldconfig
WORKDIR /frr

RUN ./configure --enable-exampledir=/usr/share/doc/frr/examples/ --localstatedir=/var/opt/frr --enable-user=frr --enable-group=frr --enable-vty-group=frrvty --disable-doc --localstatedir=/var/run/frr --sbindir=/usr/lib/frr --sysconfdir=/etc/frr --enable-systemd
RUN make
RUN make check
RUN make install

RUN install -m 755 -o frr -g frr -d /var/log/frr
RUN install -m 755 -o frr -g frr -d /var/opt/frr
RUN install -m 775 -o frr -g frrvty -d /etc/frr
RUN install -m 640 -o frr -g frr /dev/null /etc/frr/zebra.conf
RUN install -m 640 -o frr -g frr /dev/null /etc/frr/bgpd.conf
RUN install -m 640 -o frr -g frr /dev/null /etc/frr/ospfd.conf
RUN install -m 640 -o frr -g frr /dev/null /etc/frr/ospf6d.conf
RUN install -m 640 -o frr -g frr /dev/null /etc/frr/isisd.conf
RUN install -m 640 -o frr -g frr /dev/null /etc/frr/ripd.conf
RUN install -m 640 -o frr -g frr /dev/null /etc/frr/ripngd.conf
RUN install -m 640 -o frr -g frr /dev/null /etc/frr/pimd.conf
RUN install -m 640 -o frr -g frr /dev/null /etc/frr/ldpd.conf
RUN install -m 640 -o frr -g frr /dev/null /etc/frr/nhrpd.conf
RUN install -m 640 -o frr -g frrvty /dev/null /etc/frr/vtysh.conf
WORKDIR /

# Set locale
RUN sed -i -e 's/# \(en_US\.UTF-8 .*\)/\1/' /etc/locale.gen && \
    locale-gen
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# To prevent the error /usr/lib/frr/watchfrr: error while loading shared libraries: libfrr.so.0: cannot open shared object file: No such file or directory when start FRR
RUN echo include /usr/local/lib >> /etc/ld.so.conf
RUN ldconfig

RUN mkdir -p /root/.ssh

# Add startup script and set it as entrypoint
COPY docker-start /usr/sbin/docker-start
COPY looking_glass.sh /home/.looking_glass.sh
RUN chmod +x /usr/sbin/docker-start
ENTRYPOINT ["/usr/sbin/docker-start"]
