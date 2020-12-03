#!/bin/bash

ip address add 10.1.1.1/24 dev 1-PARA
ip route add default via 10.1.1.2
