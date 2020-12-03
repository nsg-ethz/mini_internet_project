#!/bin/bash

vtysh << EOM
conf t
interface lo
ip address 20.152.0.1/24
exit
router ospf
ospf router-id 20.152.0.1
network 20.152.0.1/24 area 0
exit
interface port_CENT1
ip address 20.0.0.2/24
ip ospf cost 1
exit
router ospf
network 20.0.0.2/24 area 0
exit
interface host
ip address 192.168.0.2/24
exit
router ospf
network 192.168.0.2/24 area 0
exit
router bgp 20
neighbor 20.151.0.1 remote-as 20
neighbor 20.151.0.1 update-source lo
address-family ipv4 unicast
network 20.0.0.0/8
neighbor 20.151.0.1 next-hop-self
exit
exit
ip route 20.0.0.0/8 Null0
exit
EOM
