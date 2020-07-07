#!/bin/bash
# Copyright (C) 2014 Nicira, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at:
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.



# original file at https://github.com/openvswitch/ovs/blob/master/utilities/ovs-docker
#
# Several changes have been made by Tino Rellstab and Thomas Holterbach
#
# The following changes have been made:
#   append ovs-vsctl add-port to ../groups/add_ports.sh
#   append all following comands to ../groups/ip_setup.sh
# this way all ports can be added in one go -> speeds up process by hours!!!
#
# The function add_port has been extended quite a lot for out platform
# We wrote the function connect_ports, so that a ovs switch can use to interconnect
# several pairs of containers (instead of one ovs switch for each pair of containers).
# Some other parts of the original file have been removed.

# Check for programs we'll need.
search_path () {
    save_IFS=$IFS
    IFS=:
    for dir in $PATH; do
        IFS=$save_IFS
        if test -x "$dir/$1"; then
            return 0
        fi
    done
    IFS=$save_IFS
    echo >&2 "$0: $1 not found in \$PATH, please install and try again"
    exit 1
}

ovs_vsctl () {
    ovs-vsctl --timeout=60 "$@"
}

create_netns_link () {
    if [ ! -e /var/run/netns ]; then
        mkdir -p /var/run/netns
    fi
    if [ ! -e /var/run/netns/"$PID" ]; then
        ln -s /proc/"$PID"/ns/net /var/run/netns/"$PID"
        trap 'delete_netns_link' 0
        for signal in 1 2 3 13 14 15; do
            trap 'delete_netns_link; trap - $signal; kill -$signal $$' $signal
        done
    fi
}

delete_netns_link () {
    rm -f /var/run/netns/"$PID"
}

source ./groups/docker_pid.map
get_docker_pid() {
    if [[ -v "DOCKER_TO_PID[$1]" ]]; then
        DOCKER_PID="${DOCKER_TO_PID[$1]}"
    else
        echo >&2 "WARNING: get_docker_pid $1 not found in cache"
        if DOCKER_PID=`docker inspect -f '{{.State.Pid}}' "$1"`; then :; else
           echo >&2 "$UTIL: Failed to get the PID of the container"
           exit 1
        fi
    fi
}

add_port () {
    BRIDGE="$1"
    INTERFACE="$2"
    CONTAINER="$3"

    if [ -z "$BRIDGE" ] || [ -z "$INTERFACE" ] || [ -z "$CONTAINER" ]; then
        echo >&2 "$UTIL add-port: not enough arguments (use --help for help)"
        exit 1
    fi

    shift 3
    while [ $# -ne 0 ]; do
        case $1 in
            --ipaddress=*)
                ADDRESS=${1#*=}
                shift
                ;;
            --macaddress=*)
                MACADDRESS=${1#*=}
                shift
                ;;
            --gateway=*)
                GATEWAY=${1#*=}
                shift
                ;;
            --mtu=*)
                MTU=${1#*=}
                shift
                ;;
            --delay=*)
                DELAY=${1#*=}
                shift
                ;;
            --throughput=*)
                THROUGHPUT=${1#*=}
                shift
                ;;
            *)
                echo >&2 "$UTIL add-port: unknown option \"$1\""
                exit 1
                ;;
        esac
    done

    get_docker_pid $CONTAINER
    PID=$DOCKER_PID

    create_netns_link

    echo "if [ \"$CONTAINER\" == \$container_name ]; then" >> groups/restart_container.sh
    echo "  echo \"Create Link for $CONTAINER ($INTERFACE) on bridge $BIRDGE\"" >> groups/restart_container.sh

    # Create a veth pair.
    ID=`uuidgen -s --namespace @url --name "${BRIDGE}_${INTERFACE}_${CONTAINER}" | sed 's/-//g'`
    PORTNAME="${ID:0:13}"

    echo "#ip link add "${PORTNAME}_l" type veth peer name "${PORTNAME}_c >> groups/ip_setup.sh

    ip link add "${PORTNAME}_l" type veth peer name "${PORTNAME}_c"
    echo "ip link delete "${PORTNAME}_l >> groups/delete_veth_pairs.sh

    # echo "  ip link delete "${PORTNAME}_l >> groups/restart_container.sh
    echo "  ip link add "${PORTNAME}_l" type veth peer name "${PORTNAME}_c >> groups/restart_container.sh

    echo "-- add-port "$BRIDGE" "${PORTNAME}_l" \\" >> groups/add_ports.sh
    echo "-- set interface "${PORTNAME}_l" external_ids:container_id="$CONTAINER" external_ids:container_iface="$INTERFACE" \\" >> groups/add_ports.sh

    echo "  ovs-vsctl del-port "$BRIDGE" "${PORTNAME}_l >> groups/restart_container.sh
    echo "  ovs-vsctl add-port "$BRIDGE" "${PORTNAME}_l >> groups/restart_container.sh
    echo "  ovs-vsctl set interface "${PORTNAME}_l" external_ids:container_id="$CONTAINER" external_ids:container_iface="$INTERFACE >> groups/restart_container.sh

    echo "ip link set "${PORTNAME}_l" up" >> groups/ip_setup.sh
    echo "  ip link set "${PORTNAME}_l" up" >> groups/restart_container.sh

    # Move "${PORTNAME}_c" inside the container and changes its name.
    echo "PID=$PID">> groups/ip_setup.sh
    echo "create_netns_link" >> groups/ip_setup.sh
    echo "ip link set "${PORTNAME}_c" netns "\$PID"" >> groups/ip_setup.sh
    echo "ip netns exec "\$PID" ip link set dev "${PORTNAME}_c" name "$INTERFACE"" >> groups/ip_setup.sh
    echo "ip netns exec "\$PID" ip link set "$INTERFACE" up" >> groups/ip_setup.sh

    echo "  PID=\$(docker inspect -f '{{.State.Pid}}' "$CONTAINER")">> groups/restart_container.sh
    echo "  create_netns_link" >> groups/restart_container.sh
    echo "  ip link set "${PORTNAME}_c" netns "\$PID"" >> groups/restart_container.sh
    echo "  ip netns exec "\$PID" ip link set dev "${PORTNAME}_c" name "$INTERFACE"" >> groups/restart_container.sh
    echo "  ip netns exec "\$PID" ip link set "$INTERFACE" up" >> groups/restart_container.sh

    if [ -n "$MTU" ]; then
        ip netns exec "$PID" ip link set dev "$INTERFACE" mtu "$MTU"
        echo "  ip netns exec "$PID" ip link set dev "$INTERFACE" mtu "$MTU >> groups/restart_container.sh
    fi

    if [ -n "$ADDRESS" ]; then
        echo "ip netns exec "\$PID" ip addr add "$ADDRESS" dev "$INTERFACE"" >> groups/ip_setup.sh
        echo "  ip netns exec "\$PID" ip addr add "$ADDRESS" dev "$INTERFACE"" >> groups/restart_container.sh
    fi

    if [ -n "$MACADDRESS" ]; then
        echo "ip netns exec "$PID" ip link set dev "$INTERFACE" address "$MACADDRESS"" >> groups/ip_setup.sh
        echo "  ip netns exec "$PID" ip link set dev "$INTERFACE" address "$MACADDRESS"" >> groups/restart_container.sh
    fi

    if [ -n "$GATEWAY" ]; then
        echo "ip netns exec "$PID" ip route add default via "$GATEWAY"" >> groups/ip_setup.sh
        echo "  ip netns exec "$PID" ip route add default via "$GATEWAY"" >> groups/restart_container.sh
    fi

    if [ -n "$DELAY" ]; then
        echo "tc qdisc add dev "${PORTNAME}"_l root netem delay "${DELAY}" " >> groups/delay_throughput.sh
        echo "  tc qdisc add dev "${PORTNAME}"_l root netem delay "${DELAY}" " >> groups/restart_container.sh
    fi

    if [ -n "$THROUGHPUT" ]; then
        echo "echo -n \" -- set interface "${PORTNAME}"_l ingress_policing_rate="${THROUGHPUT}" \" >> groups/throughput.sh " >> groups/delay_throughput.sh
        echo "  ovs-vsctl set interface ${PORTNAME}_l ingress_policing_rate=${THROUGHPUT}" >> groups/restart_container.sh
    fi

    echo "fi" >> groups/restart_container.sh

}

connect_ports () {
    BRIDGE="$1"
    INTERFACE1="$2"
    CONTAINER1="$3"
    INTERFACE2="$4"
    CONTAINER2="$5"

    if [ -z "$BRIDGE" ] || [ -z "$INTERFACE1" ] || [ -z "$CONTAINER1" ] || [ -z "$INTERFACE2" ] || [ -z "$CONTAINER2" ]; then
        echo >&2 "$UTIL connect-ports: not enough arguments (use --help for help)"
        exit 1
    fi

    ID1=`uuidgen -s --namespace @url --name ${BRIDGE}_${INTERFACE1}_${CONTAINER1} | sed 's/-//g'`
    PORTNAME1="${ID1:0:13}"
    ID2=`uuidgen -s --namespace @url --name ${BRIDGE}_${INTERFACE2}_${CONTAINER2} | sed 's/-//g'`
    PORTNAME2="${ID2:0:13}"

    echo "port_id1=\`ovs-vsctl get Interface ${PORTNAME1}_l ofport\`" >> groups/ip_setup.sh
    echo "port_id2=\`ovs-vsctl get Interface ${PORTNAME2}_l ofport\`" >> groups/ip_setup.sh

    echo "ovs-ofctl add-flow $BRIDGE in_port=\$port_id1,actions=output:\$port_id2" >> groups/ip_setup.sh
    echo "ovs-ofctl add-flow $BRIDGE in_port=\$port_id2,actions=output:\$port_id1" >> groups/ip_setup.sh

    echo "if [ \"$CONTAINER1\" == \$container_name ] || [ \"$CONTAINER2\" == \$container_name ]; then" >> groups/restart_container.sh
    echo "  echo \"Link between $CONTAINER1 ($INTERFACE1) and $CONTAINER2 ($INTERFACE2)\"" >> groups/restart_container.sh

    echo "  port_id1=\`ovs-vsctl get Interface ${PORTNAME1}_l ofport\`" >> groups/restart_container.sh
    echo "  port_id2=\`ovs-vsctl get Interface ${PORTNAME2}_l ofport\`" >> groups/restart_container.sh

    echo "  ovs-ofctl add-flow $BRIDGE in_port=\$port_id1,actions=output:\$port_id2" >> groups/restart_container.sh
    echo "  ovs-ofctl add-flow $BRIDGE in_port=\$port_id2,actions=output:\$port_id1" >> groups/restart_container.sh

    echo "fi" >> groups/restart_container.sh

}

UTIL=${0##*/}

if [ "$1" == "add-port" ]; then
    shift
    add_port "$@"
elif [ "$1" == "connect-ports" ]; then
    shift
    connect_ports "$@"
fi
