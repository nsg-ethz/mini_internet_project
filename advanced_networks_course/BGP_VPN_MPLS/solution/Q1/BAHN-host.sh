#!/bin/bash

ip address add 10.1.0.1/16 dev 1-BAHN
ip route add default via 10.1.0.2
