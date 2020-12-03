#!/bin/bash

vtysh << EOM
conf t
interface ext_1_R4
ip address 179.0.1.2/24
exit
interface host
ip address 30.101.0.2/24
exit
route-map ACCEPT permit 10
exit
router bgp 30
neighbor 179.0.1.1 remote-as 1
address-family ipv4 unicast
network 30.0.0.0/8
neighbor 179.0.1.1 route-map ACCEPT in
neighbor 179.0.1.1 route-map ACCEPT out
exit
exit
ip route 30.0.0.0/8 Null0
exit
EOM
