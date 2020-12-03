#!/bin/bash

vtysh << EOM
conf t
mpls ldp
router-id 1.155.0.1
address-family ipv4
discovery transport-address 1.155.0.1
interface port_R1
interface port_R2
interface port_R3
interface port_R4
exit
exit
exit
exit
EOM
