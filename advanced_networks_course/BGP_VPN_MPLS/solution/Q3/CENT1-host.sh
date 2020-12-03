#!/bin/bash

ip address add 10.1.0.1/24 dev CENT1router
ip route add default via 10.1.0.2
