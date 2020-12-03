#!/bin/bash

ip address add 10.0.0.1/16 dev 1-BELLE
ip route add default via 10.0.0.2
