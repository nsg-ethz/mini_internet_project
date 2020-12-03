#!/bin/bash

ip address add 192.168.1.1/24 dev 1-OERL
ip route add default via 192.168.1.2
