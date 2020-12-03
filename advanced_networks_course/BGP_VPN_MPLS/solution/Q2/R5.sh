#!/bin/bash

vtysh << EOM
conf t
interface lo
ip address 1.155.0.1/32
exit
router ospf
ospf router-id 1.155.0.1
network 1.155.0.1/32 area 0
exit
interface host
ip address 1.105.0.2/24
ip ospf cost 1
exit
router ospf
network 1.105.0.2/24 area 0
exit
interface port_R1
ip address 1.0.2.2/24
ip ospf cost 1
exit
router ospf
network 1.0.2.2/24 area 0
exit
interface port_R2
ip address 1.0.3.2/24
ip ospf cost 1
exit
router ospf
network 1.0.3.2/24 area 0
exit
interface port_R3
ip address 1.0.5.2/24
ip ospf cost 100
exit
router ospf
network 1.0.6.2/24 area 0
exit
interface port_R4
ip address 1.0.7.1/24
ip ospf cost 1
exit
router ospf
network 1.0.7.1/24 area 0
exit
mpls ldp
router-id 1.155.0.1
address-family ipv4
discovery transport-address 1.155.0.1
label local allocate host-routes
interface port_R1
interface port_R2
interface port_R3
interface port_R4
exit
exit
exit
exit
EOM
