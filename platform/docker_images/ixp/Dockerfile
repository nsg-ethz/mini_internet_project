FROM phusion/baseimage:0.9.16

# Install dependencies
RUN apt-get update && apt-get install -y curl wget openvswitch-switch openvswitch-common \
     vim openssh-server inetutils-traceroute net-tools tcpdump quagga

RUN echo "export VTYSH_PAGER=more" >>  /etc/bash.bashrc
RUN echo "VTYSH_PAGER=more" >> /etc/environment

RUN	touch /etc/quagga/bgpd.conf && \
	touch /etc/quagga/ospfd.conf && \
	touch /etc/quagga/vtysh.conf && \
	touch /etc/quagga/zebra.conf


# Add startup script and set it as entrypoint
ADD docker-start /usr/sbin/docker-start
RUN chmod +x /usr/sbin/docker-start
ENTRYPOINT ["/usr/sbin/docker-start"]
