#!/bin/bash

vtysh << EOM
conf t
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
