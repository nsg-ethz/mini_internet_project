#!/bin/bash

vtysh << EOM
conf t
route-map ACCEPT permit 10
exit
router bgp 20
neighbor 179.0.0.2 remote-as 1
address-family ipv4 unicast
neighbor 179.0.0.2 route-map ACCEPT in
neighbor 179.0.0.2 route-map ACCEPT out
network 10.1.0.0/24
network 192.168.0.0/24
exit
exit
ip route 0.0.0.0/0 179.0.0.2
exit
EOM
