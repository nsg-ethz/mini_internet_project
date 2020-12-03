#!/bin/bash

vtysh << EOM
conf t
route-map ACCEPT permit 10
exit
ip prefix-list CS_PREFIX seq 5 permit 20.0.0.0/8
route-map ROUTEMAP_CS permit 10
match ip address prefix-list CS_PREFIX
exit
router bgp 1
neighbor 1.152.0.1 remote-as 1
neighbor 1.152.0.1 update-source lo
neighbor 1.153.0.1 remote-as 1
neighbor 1.153.0.1 update-source lo
neighbor 1.154.0.1 remote-as 1
neighbor 1.154.0.1 update-source lo
address-family ipv4 unicast
network 1.0.0.0/8
network 20.0.0.0/8
neighbor 1.152.0.1 next-hop-self
neighbor 1.153.0.1 next-hop-self
neighbor 1.154.0.1 next-hop-self
export vpn
import vpn
label vpn export auto
rd vpn export 1:1
rt vpn export 1:1
rt vpn import 20:1
route-map vpn import ROUTEMAP_CS
exit
address-family ipv4 vpn
neighbor 1.152.0.1 activate
neighbor 1.153.0.1 activate
neighbor 1.154.0.1 activate
exit
exit
router bgp 1 vrf VRF_CS
neighbor 179.0.0.1 remote-as 20
address-family ipv4 unicast
neighbor 179.0.0.1 route-map ACCEPT in
neighbor 179.0.0.1 route-map ACCEPT out
label vpn export auto
rd vpn export 20:1
rt vpn export 20:1
rt vpn import 20:2 20:3 1:1
export vpn
import vpn
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
router-id 1.151.0.1
address-family ipv4
discovery transport-address 1.151.0.1
interface port_R2
interface port_R3
interface port_R5
exit
exit
exit
exit
EOM
