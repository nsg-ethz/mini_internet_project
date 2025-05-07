#!/bin/bash
# This script aims at mitigating potential DDos-like attacks
# targeting the mini-Internet webservers and ssh ports.
# Most of rules come from: https://javapipe.com/blog/iptables-ddos-protection/

###########################################
### READ ARGUMENTS WITH DEFAULT VALUES  ###
###########################################
CONFIG_DIR="${1:-$(pwd)}"
action="${2:--A}" # or -D to undo
SSH_PORT_BASE="${3:-2000}"
WEBSERVER_ARG="${4:-80,443}"
KRILL_PORT="${5:-3080}"

# Convert comma-separated WEBSERVER_ARG to array
IFS=',' read -ra WEBSERVER_PORTS <<< "$WEBSERVER_ARG"

# Block Invalid Packets
iptables -t mangle $action PREROUTING -m conntrack --ctstate INVALID -j DROP
iptables -t mangle $action PREROUTING -p tcp ! --syn -m conntrack --ctstate NEW -j DROP
iptables -t mangle $action PREROUTING -p tcp -m conntrack --ctstate NEW -m tcpmss ! --mss 536:65535 -j DROP

# Block Packets With Bogus TCP Flags
iptables -t mangle $action PREROUTING -p tcp --tcp-flags FIN,SYN FIN,SYN -j DROP
iptables -t mangle $action PREROUTING -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
iptables -t mangle $action PREROUTING -p tcp --tcp-flags FIN,RST FIN,RST -j DROP
iptables -t mangle $action PREROUTING -p tcp --tcp-flags FIN,ACK FIN -j DROP
iptables -t mangle $action PREROUTING -p tcp --tcp-flags ACK,URG URG -j DROP
iptables -t mangle $action PREROUTING -p tcp --tcp-flags ACK,PSH PSH -j DROP
iptables -t mangle $action PREROUTING -p tcp --tcp-flags ALL NONE -j DROP

# Webserver protection rules
for port in "${WEBSERVER_PORTS[@]}"; do
    iptables $action INPUT -p tcp --dport "$port" -m connlimit --connlimit-above 20 -j REJECT --reject-with tcp-reset
    iptables $action INPUT -p tcp --dport "$port" -m conntrack --ctstate NEW -m limit --limit 60/s --limit-burst 20 -j ACCEPT
    iptables $action INPUT -p tcp --dport "$port" -m conntrack --ctstate NEW -j DROP
done

# Krill port protection
iptables $action INPUT -p tcp --dport "$KRILL_PORT" -m connlimit --connlimit-above 20 -j REJECT --reject-with tcp-reset
iptables $action INPUT -p tcp --dport "$KRILL_PORT" -m conntrack --ctstate NEW -m limit --limit 60/s --limit-burst 20 -j ACCEPT
iptables $action INPUT -p tcp --dport "$KRILL_PORT" -m conntrack --ctstate NEW -j DROP

# Block fragmented packets
iptables -t mangle $action PREROUTING -f -j DROP

# Limit incoming TCP RST packets
iptables $action INPUT -p tcp --tcp-flags RST RST -m limit --limit 2/s --limit-burst 2 -j ACCEPT
iptables $action INPUT -p tcp --tcp-flags RST RST -j DROP

# SSH brute-force protection
readarray groups < "$CONFIG_DIR/AS_config.txt"
group_numbers=${#groups[@]}

for ((k=0;k<group_numbers;k++)); do
    group_k=(${groups[$k]})
    group_number="${group_k[0]}"
    group_as="${group_k[1]}"

    if [ "${group_as}" != "IXP" ]; then
        ssh_port=$(($SSH_PORT_BASE + $group_number))
        iptables $action INPUT -p tcp --dport "$ssh_port" -m conntrack --ctstate NEW -m recent --set
        iptables $action INPUT -p tcp --dport "$ssh_port" -m conntrack --ctstate NEW -m recent --update --seconds 60 --hitcount 10 -j DROP
    fi
done

# Protection against port scanning
iptables -N port-scanning 2>/dev/null
iptables $action port-scanning -p tcp --tcp-flags SYN,ACK,FIN,RST RST -m limit --limit 1/s --limit-burst 2 -j RETURN
iptables $action port-scanning -j DROP
