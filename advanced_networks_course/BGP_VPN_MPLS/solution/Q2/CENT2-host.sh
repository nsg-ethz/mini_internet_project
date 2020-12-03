#!/bin/bash

ip address add 192.168.0.1/24 dev CENT2router
ip route add default via 192.168.0.2
