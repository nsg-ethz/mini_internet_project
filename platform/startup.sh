#!/bin/bash
#
# starts whole network

set -o errexit
set -o pipefail
set -o nounset

# Check for programs we'll need.
search_path () {
    type -p "$1" > /dev/null && return 0
    echo >&2 "$0: $1 not found in \$PATH, please install and try again"
    exit 1
}

if (($UID != 0)); then
    echo "$0 needs to be run as root"
    exit 1
fi

search_path ovs-vsctl
search_path docker
search_path uuidgen

if (ip netns) > /dev/null 2>&1; then :; else
    echo >&2 "${0##*/}: ip utility not found (or it does not support netns),"\
             "cannot proceed"
    exit 1
fi

DIRECTORY=$(cd `dirname $0` && pwd)
DOCKERHUB_USER="miniinterneteth"

echo "$(date +%Y-%m-%d_%H-%M-%S)"

echo "cleanup.sh: "
time ./cleanup/cleanup.sh "${DIRECTORY}"

echo ""
echo ""

# change size of ARP table necessary for large networks
sysctl net.ipv4.neigh.default.gc_thresh1=16384
sysctl net.ipv4.neigh.default.gc_thresh2=32768
sysctl net.ipv4.neigh.default.gc_thresh3=131072
sysctl -p

# Increase the max number of running processes
sysctl kernel.pid_max=4194304

# Load MPLS kernel modules
modprobe mpls_router
modprobe mpls_gso
modprobe mpls_iptunnel

echo "folder_setup.sh $(($(date +%s%N)/1000000))" > "${DIRECTORY}"/log.txt
echo "folder_setup.sh: "
time ./setup/folder_setup.sh "${DIRECTORY}"

echo ""
echo ""

echo "dns_config.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
echo "dns_config.sh: "
time ./setup/dns_config.sh "${DIRECTORY}"

echo ""
echo ""

echo "rpki_config.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
echo "rpki_config.sh: "
time ./setup/rpki_config.sh "${DIRECTORY}"

echo ""
echo ""

echo "vpn_config.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
echo "vpn_config.sh: "
time ./setup/vpn_config.sh "${DIRECTORY}"

echo ""
echo ""

echo "goto_scripts.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
echo "goto_scripts.sh: "
time ./setup/goto_scripts.sh "${DIRECTORY}"

echo ""
echo ""

echo "save_configs.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
echo "save_configs.sh: "
time ./setup/save_configs.sh "${DIRECTORY}"

echo ""
echo ""

echo "container_setup.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
echo "container_setup.sh: "
time ./setup/container_setup.sh "${DIRECTORY}" "${DOCKERHUB_USER}"

echo ""
echo ""

echo "echo \"host links\"" >> "${DIRECTORY}"/groups/ip_setup.sh
echo "host_links_setup.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
echo "host_links_setup.sh: "
time ./setup/host_links_setup.sh "${DIRECTORY}"

echo ""
echo ""

echo "echo \"layer2 links\"" >> "${DIRECTORY}"/groups/ip_setup.sh
echo "layer2_setup.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
echo "layer2_setup.sh: "
time ./setup/layer2_setup.sh "${DIRECTORY}"

echo ""
echo ""

echo "echo \"internal links\"" >> "${DIRECTORY}"/groups/ip_setup.sh
echo "internal_links_setup.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
echo "internal_links_setup.sh: "
time ./setup/internal_links_setup.sh "${DIRECTORY}"

echo ""
echo ""

echo "echo \"external links\"" >> "${DIRECTORY}"/groups/ip_setup.sh
echo "external_links_setup.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
echo "external_links_setup.sh: "
time ./setup/external_links_setup.sh "${DIRECTORY}"

echo ""
echo ""

echo "echo \"measurement links\"" >> "${DIRECTORY}"/groups/ip_setup.sh
echo "measurement_setup.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
echo "measurement_setup.sh: "
time ./setup/measurement_setup.sh "${DIRECTORY}" "${DOCKERHUB_USER}"

echo ""
echo ""

echo "echo \"ssh links\"" >> "${DIRECTORY}"/groups/ip_setup.sh
echo "ssh_setup.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
echo "ssh_setup.sh: "
time ./setup/ssh_setup.sh "${DIRECTORY}"

echo ""
echo ""

echo "echo \"matrix_setup\"" >> "${DIRECTORY}"/groups/ip_setup.sh
echo "matrix_setup.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
echo "matrix_setup.sh: "
time ./setup/matrix_setup.sh "${DIRECTORY}" "${DOCKERHUB_USER}"

echo ""
echo ""

echo "echo \"dns links\"" >> "${DIRECTORY}"/groups/ip_setup.sh
echo "dns_setup.sh: "
echo "dns_setup.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
time ./setup/dns_setup.sh "${DIRECTORY}" "${DOCKERHUB_USER}"

echo ""
echo ""

echo "add_bridges.sh: "
echo "add_bridges.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
time ./groups/add_bridges.sh

echo ""
echo ""

echo "add_ports.sh: "
echo "add_ports.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
time ./groups/add_ports.sh

echo ""
echo ""

echo "ip_setup.sh: "
echo "ip_setup.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
time ./groups/ip_setup.sh
sleep 10

echo ""
echo ""

echo "dns_routes.sh"
echo "dns_routes $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
time ./groups/dns_routes.sh

echo ""
echo ""

echo "l2_init_switch.sh: "
echo "l2_init_switch.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
time ./groups/l2_init_switch.sh

echo ""
echo ""

echo "add_vpns.sh: "
echo "add_vpns.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
time ./groups/add_vpns.sh

echo ""
echo ""

echo "layer2_config.sh: "
echo "layer2_config.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
time ./setup/layer2_config.sh "${DIRECTORY}"

echo ""
echo ""

echo "router_config.sh: "
echo "router_config.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
time ./setup/router_config.sh "${DIRECTORY}"

echo ""
echo ""

echo "mpls.sh: "
echo "mpls.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
time ./setup/mpls_setup.sh "${DIRECTORY}"

echo ""
echo ""

echo "Waiting 60sec for RPKI CA and proxy to startup.."
sleep 60

echo "rpki_setup.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
echo "rpki_setup.sh: "
time ./setup/rpki_setup.sh "${DIRECTORY}"

echo ""
echo ""

echo "website_setup.sh: "
echo "website_setup.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
time ./setup/website_setup.sh "${DIRECTORY}" "${DOCKERHUB_USER}"

echo ""
echo ""

echo "webserver_links.sh: "
echo "webserver_links.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
time ./groups/rpki/webserver_links.sh

echo ""
echo ""

echo "wait" >> "${DIRECTORY}"/groups/delay_throughput.sh
echo "delay_throughput.sh: "
echo "delay_throughput.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
time ./groups/delay_throughput.sh

echo ""
echo ""

echo "throughput.sh: "
echo "throughput.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
time ./groups/throughput.sh

echo "Run ./groups/open_vpn_ports.sh to open the ports used by the vpn servers."
echo "END $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt

echo ""
echo ""

# reload dns server config
if [ -n "$(docker ps | grep "DNS")" ]; then
    # docker exec -d DNS service bind9 restart
    docker kill --signal=HUP DNS
fi

echo "$(date +%Y-%m-%d_%H-%M-%S)"
