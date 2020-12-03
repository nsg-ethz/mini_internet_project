#!/bin/bash

ip address add 1.105.0.1/24 dev R5router
ip route add default via 1.105.0.2
