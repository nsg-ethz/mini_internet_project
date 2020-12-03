#!/bin/bash

ip address add 30.101.0.1/24 dev S1router
ip route add default via 30.101.0.2
