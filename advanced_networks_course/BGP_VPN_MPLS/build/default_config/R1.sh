#!/bin/bash

ip link add VRF_CS type vrf table 10
ip link set dev VRF_CS up
ip link set ext_20_CENT1 master VRF_CS

ip link add VRF_UBS type vrf table 20
ip link set dev VRF_UBS up
ip link set R1-L2 master VRF_UBS

vtysh << EOM
conf t
interface lo
ip address 1.151.0.1/32
exit
router ospf
ospf router-id 1.151.0.1
network 1.151.0.1/32 area 0
exit
interface port_R2
ip address 1.0.0.1/24
ip ospf cost 100
exit
router ospf
network 1.0.0.1/24 area 0
exit
interface port_R3
ip address 1.0.1.1/24
ip ospf cost 1
exit
router ospf
network 1.0.1.1/24 area 0
exit
interface port_R5
ip address 1.0.2.1/24
ip ospf cost 1
exit
router ospf
network 1.0.2.1/24 area 0
exit
interface R1-L2
ip address 10.0.0.2/16
ip ospf cost 1
exit
interface ext_20_CENT1
ip address 179.0.0.2/24
exit
ip route 1.0.0.0/8 Null0
exit
EOM
