#!/bin/bash

ip link add VRF_CS type vrf table 10
ip link set dev VRF_CS up
ip link set R2-L2 master VRF_CS

vtysh << EOM
conf t
interface lo
ip address 1.152.0.1/32
exit
router ospf
ospf router-id 1.152.0.1
network 1.152.0.1/32 area 0
exit
interface port_R1
ip address 1.0.0.2/24
ip ospf cost 100
exit
router ospf
network 1.0.0.2/24 area 0
exit
interface port_R4
ip address 1.0.4.1/24
ip ospf cost 1
exit
router ospf
network 1.0.4.1/24 area 0
exit
interface port_R5
ip address 1.0.3.1/24
ip ospf cost 1
exit
router ospf
network 1.0.3.1/24 area 0
exit
interface R2-L2
ip address 192.168.1.2/24
exit
ip route 1.0.0.0/8 Null0
exit
EOM
