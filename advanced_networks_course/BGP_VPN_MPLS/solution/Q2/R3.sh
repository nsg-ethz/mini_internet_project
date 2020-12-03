#!/bin/bash

ip link add VRF_CS type vrf table 10
ip link set dev VRF_CS up
ip link set R3-L2 master VRF_CS

vtysh << EOM
conf t
interface lo
ip address 1.153.0.1/32
exit
router ospf
ospf router-id 1.153.0.1
network 1.153.0.1/32 area 0
exit
interface port_R1
ip address 1.0.1.2/24
ip ospf cost 1
exit
router ospf
network 1.0.1.2/24 area 0
exit
interface port_R4
ip address 1.0.6.1/24
ip ospf cost 100
exit
router ospf
network 1.0.6.1/24 area 0
exit
interface port_R5
ip address 1.0.5.1/24
ip ospf cost 100
exit
router ospf
network 1.0.5.1/24 area 0
exit
interface R3-L2
ip address 10.1.1.2/24
exit
router bgp 1
neighbor 1.151.0.1 remote-as 1
neighbor 1.151.0.1 update-source lo
neighbor 1.152.0.1 remote-as 1
neighbor 1.152.0.1 update-source lo
neighbor 1.154.0.1 remote-as 1
neighbor 1.154.0.1 update-source lo
address-family ipv4 unicast
network 1.0.0.0/8
neighbor 1.151.0.1 next-hop-self
neighbor 1.152.0.1 next-hop-self
neighbor 1.154.0.1 next-hop-self
exit
address-family ipv4 vpn
neighbor 1.151.0.1 activate
neighbor 1.152.0.1 activate
neighbor 1.154.0.1 activate
exit
exit
router bgp 1 vrf VRF_CS
address-family ipv4 unicast
redistribute connected
label vpn export auto
rd vpn export 20:1
rt vpn both 20:1
export vpn
import vpn
exit
exit
mpls ldp
router-id 1.153.0.1
address-family ipv4
discovery transport-address 1.153.0.1
interface port_R1
interface port_R4
interface port_R5
exit
exit
exit
exit
EOM
