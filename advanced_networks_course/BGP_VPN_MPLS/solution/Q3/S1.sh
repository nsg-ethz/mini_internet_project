#!/bin/bash

vtysh << EOM
conf t
interface ext_1_R4
ip address 179.0.1.2/24
exit
route-map ACCEPT permit 10
exit
router bgp 30
neighbor 179.0.1.1 remote-as 1
address-family ipv4 unicast
neighbor 179.0.1.1 route-map ACCEPT in
neighbor 179.0.1.1 route-map ACCEPT out
exit
exit
exit
EOM
