#!/bin/bash

vtysh << EOM
conf t
ip route 0.0.0.0/0 20.0.0.1
exit
EOM
