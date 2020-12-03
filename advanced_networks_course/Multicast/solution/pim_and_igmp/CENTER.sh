#!/bin/bash

###############################################################################
# Write your configuration commands below.
# Every line between the two "EOM" tokens will be redirected (entered) into the
# router vtysh, just as if you'd type them line after line.
#
# If you have not seen this syntax for multiline strings in bash before:
# It is called "heredoc" and you can find a short tutorial here:
# https://linuxhint.com/bash-heredoc-tutorial/
###############################################################################

vtysh << EOM
conf t
ip pim rp 1.156.0.1 237.0.0.0/24
interface host
ip pim
exit
interface port_TOP
ip pim
exit
interface port_LEFT
ip pim
exit
interface port_RIGHT
ip pim
exit
interface port_BOTTOML
ip pim
exit
interface port_BOTTOMR
ip pim
exit
interface lo
ip pim
exit
exit
exit
EOM
