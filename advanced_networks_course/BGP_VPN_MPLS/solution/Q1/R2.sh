#!/bin/bash

vtysh << EOM
conf t
router bgp 1
neighbor 1.151.0.1 remote-as 1
neighbor 1.151.0.1 update-source lo
neighbor 1.153.0.1 remote-as 1
neighbor 1.153.0.1 update-source lo
neighbor 1.154.0.1 remote-as 1
neighbor 1.154.0.1 update-source lo
address-family ipv4 unicast
network 1.0.0.0/8
neighbor 1.151.0.1 next-hop-self
neighbor 1.153.0.1 next-hop-self
neighbor 1.154.0.1 next-hop-self
exit
exit
mpls ldp
router-id 1.152.0.1
address-family ipv4
discovery transport-address 1.152.0.1
interface port_R1
interface port_R4
interface port_R5
exit
exit
exit
exit
EOM
