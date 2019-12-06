#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

PORTNAME="nat_port"

sudo ip link add "${PORTNAME}_l" type veth peer name "${PORTNAME}_c"
sudo ip link set "${PORTNAME}_l" up

PID=$(sudo docker inspect -f '{{.State.Pid}}' 1_FRANrouter)
sudo ip link set "${PORTNAME}_c" netns $PID
sudo ip netns exec $PID ip link set dev "${PORTNAME}_c" name nat
sudo ip netns exec $PID ip link set nat up

sudo ifconfig ${PORTNAME}_l 1.0.13.2/16
sudo ifconfig ${PORTNAME}_l hw ether 08:55:55:55:55:01
sudo ifconfig enp1s0f1 200.200.0.1/24

# In 1_FRANrouter
sudo arp -s 1.0.13.2 08:55:55:55:55:01
vtysh
conf t
interface nat
ip address 1.0.13.1/24
exit
router bgp 1
address-family ipv4 unicast
network 200.200.0.0/16
exit
ip route 200.200.0.0/16 1.0.13.2
exit
exit

# Configure NAT on the main host
sudo iptables -t nat -A POSTROUTING -o enp1s0f1 -j MASQUERADE
sudo iptables -A FORWARD -i nat_port_l -j ACCEPT
