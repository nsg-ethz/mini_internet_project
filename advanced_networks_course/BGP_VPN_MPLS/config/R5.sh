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
exit
EOM
