#!/bin/bash
# This script aims at mitigating potential DDos-like attacks
# targeting the mini-Internet webservers and ssh ports. 
# Most of rules come from: https://javapipe.com/blog/iptables-ddos-protection/

CONFIG_DIR=/home/thomas/mini_internet_project/platform/config
SSH_PORT_BASE=2000
WEBSERVER_PORT=80
KRILL_PORT=3080

action='-A' # or -D to undo

# Block Invalid Packets
iptables -t mangle $action PREROUTING -m conntrack --ctstate INVALID -j DROP
# Block New Packets That Are Not SYN
iptables -t mangle $action PREROUTING -p tcp ! --syn -m conntrack --ctstate NEW -j DROP
# Block Uncommon MSS Values
iptables -t mangle $action PREROUTING -p tcp -m conntrack --ctstate NEW -m tcpmss ! --mss 536:65535 -j DROP

# # Block Packets With Bogus TCP Flags
iptables -t mangle $action PREROUTING -p tcp --tcp-flags FIN,SYN FIN,SYN -j DROP
iptables -t mangle $action PREROUTING -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
iptables -t mangle $action PREROUTING -p tcp --tcp-flags FIN,RST FIN,RST -j DROP
iptables -t mangle $action PREROUTING -p tcp --tcp-flags FIN,ACK FIN -j DROP
iptables -t mangle $action PREROUTING -p tcp --tcp-flags ACK,URG URG -j DROP
iptables -t mangle $action PREROUTING -p tcp --tcp-flags ACK,PSH PSH -j DROP
iptables -t mangle $action PREROUTING -p tcp --tcp-flags ALL NONE -j DROP

# # Reject connections if host has more than 10 established connections
iptables $action INPUT -p tcp --dport $WEBSERVER_PORT -m connlimit --connlimit-above 20 -j REJECT --reject-with tcp-reset
iptables $action INPUT -p tcp --dport $KRILL_PORT -m connlimit --connlimit-above 20 -j REJECT --reject-with tcp-reset

# # Limits the new TCP connections that a client can establish per second
iptables $action INPUT -p tcp --dport $WEBSERVER_PORT -m conntrack --ctstate NEW -m limit --limit 60/s --limit-burst 20 -j ACCEPT 
iptables $action INPUT -p tcp --dport $WEBSERVER_PORT -m conntrack --ctstate NEW -j DROP
iptables $action INPUT -p tcp --dport $KRILL_PORT -m conntrack --ctstate NEW -m limit --limit 60/s --limit-burst 20 -j ACCEPT 
iptables $action INPUT -p tcp --dport $KRILL_PORT -m conntrack --ctstate NEW -j DROP

# # This rule blocks fragmented packets
iptables -t mangle $action PREROUTING -f -j DROP

# # This limits incoming TCP RST packets to mitigate TCP RST floods
iptables $action INPUT -p tcp --tcp-flags RST RST -m limit --limit 2/s --limit-burst 2 -j ACCEPT 
iptables $action INPUT -p tcp --tcp-flags RST RST -j DROP

# ### SSH brute-force protection ### 
# read mini-Internet configs.
readarray groups < $CONFIG_DIR/AS_config.txt
group_numbers=${#groups[@]}

# Copy routers config for every group.
for ((k=0;k<group_numbers;k++)); do
    group_k=(${groups[$k]})
    group_number="${group_k[0]}"
    group_as="${group_k[1]}"
    
    if [ "${group_as}" != "IXP" ];then
        iptables $action INPUT -p tcp --dport $(($SSH_PORT_BASE+$group_number)) -m conntrack --ctstate NEW -m recent --set 
        iptables $action INPUT -p tcp --dport $(($SSH_PORT_BASE+$group_number)) -m conntrack --ctstate NEW -m recent --update --seconds 60 --hitcount 10 -j DROP  
    fi
done

# ### Protection against port scanning ### 
iptables -N port-scanning 
iptables $action port-scanning -p tcp --tcp-flags SYN,ACK,FIN,RST RST -m limit --limit 1/s --limit-burst 2 -j RETURN 
iptables $action port-scanning -j DROP