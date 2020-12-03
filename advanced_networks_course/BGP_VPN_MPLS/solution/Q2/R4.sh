#!/bin/bash

ip link add VRF_UBS type vrf table 20
ip link set dev VRF_UBS up
ip link set R4-L2 master VRF_UBS

vtysh << EOM
conf t
interface lo
ip address 1.154.0.1/32
exit
router ospf
ospf router-id 1.154.0.1
network 1.154.0.1/32 area 0
exit
interface port_R2
ip address 1.0.4.2/24
ip ospf cost 1
exit
router ospf
network 1.0.4.2/24 area 0
exit
interface port_R3
ip address 1.0.6.2/24
ip ospf cost 100
exit
router ospf
network 1.0.6.2/24 area 0
exit
interface port_R5
ip address 1.0.7.2/24
ip ospf cost 1
exit
router ospf
network 1.0.7.2/24 area 0
exit
interface R4-L2
ip address 10.1.0.2/16
exit
interface ext_30_S1
ip address 179.0.1.1/24
exit
route-map ACCEPT permit 10
exit
router bgp 1
neighbor 179.0.1.2 remote-as 30
neighbor 1.151.0.1 remote-as 1
neighbor 1.151.0.1 update-source lo
neighbor 1.152.0.1 remote-as 1
neighbor 1.152.0.1 update-source lo
neighbor 1.153.0.1 remote-as 1
neighbor 1.153.0.1 update-source lo
address-family ipv4 unicast
network 1.0.0.0/8
neighbor 179.0.1.2 route-map ACCEPT in
neighbor 179.0.1.2 route-map ACCEPT out
neighbor 1.151.0.1 next-hop-self
neighbor 1.152.0.1 next-hop-self
neighbor 1.153.0.1 next-hop-self
exit
address-family ipv4 vpn
neighbor 1.151.0.1 activate
neighbor 1.152.0.1 activate
neighbor 1.153.0.1 activate
exit
exit
router bgp 1 vrf VRF_UBS
address-family ipv4 unicast
redistribute connected
label vpn export auto
rd vpn export 30:1
rt vpn both 30:1
export vpn
import vpn
exit
exit
mpls ldp
router-id 1.154.0.1
address-family ipv4
discovery transport-address 1.154.0.1
interface port_R2
interface port_R3
interface port_R5
exit
exit
exit
exit
EOM
