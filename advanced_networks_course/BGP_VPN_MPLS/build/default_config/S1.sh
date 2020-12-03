#!/bin/bash

vtysh << EOM
conf t
interface host
ip address 30.101.0.2/24
exit
interface ext_1_R4
ip address 179.0.1.2/24
exit
router bgp 30
address-family ipv4 unicast
network 30.0.0.0/8
exit
exit
ip route 30.0.0.0/8 Null0
exit
EOM
