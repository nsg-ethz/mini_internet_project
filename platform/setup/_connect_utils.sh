#!/bin/bash

# sanity check
# set -x
trap 'exit 1' ERR
set -o errexit
set -o pipefail
set -o nounset

UTIL=${0##*/} # the name of this script

# delete the symlink for the container namespace
delete_netns_symlink() {
    rm -f /var/run/netns/"$PID"
}

# create a symlink for the container namespace
create_netns_symlink() {

    if (($UID != 0)); then
        echo "$0 needs to be run as root"
        exit 1
    fi

    if [ "$#" -ne 1 ]; then
        echo "Usage: create_netns_symlink <PID>"
        exit 1
    fi

    PID=$1 # cannot be local as it is used in the trap
    if [ ! -e /var/run/netns ]; then
        mkdir -p /var/run/netns
    fi
    if [ ! -e /var/run/netns/"$PID" ]; then
        # create the symlink for the namespace for easy management with `ip netns`
        ln -s /proc/"$PID"/ns/net /var/run/netns/"$PID"
        # delete the symlink when the script exits
        trap 'delete_netns_symlink' 0
        for signal in 1 2 3 13 14 15; do
            trap 'delete_netns_symlink; trap - $signal; kill -$signal $$' $signal
        done
    fi
}

# create a unique port name used in interface names of a veth pair
create_unique_port_name() {

    if [ "$#" -ne 1 ]; then
        echo "Usage: create_unique_port_name <Identifier>"
        exit 1
    fi

    local identifier=$1
    if [[ $(lsb_release -rs) == ^16* ]]; then
        ID=$(echo "${identifier}" | sha1sum | sed 's/-//g') # remove dash
    else
        ID=$(uuidgen -s --namespace @url --name "${identifier}" | sed 's/-//g')
    fi
    echo "${ID:0:13}"
}

# get the PID of the container
# if the cached flag is set to true, return the cached PID in DOCKER_TO_PID
# assuming DOCKER_TO_PID has been sourced.
get_container_pid() {

    if (($UID != 0)); then
        echo "$0 needs to be run as root"
        exit 1
    fi

    if [ "$#" -ne 2 ]; then
        echo "Usage: get_container_pid <ContainerName> <UseCache>"
        exit 1
    fi

    local container=$1
    local use_cache=$2

    # necesssary to have the cache, otherwise cannot get the old PID
    # for a stopped container
    if [ "$use_cache" = "True" ]; then
        if [[ -v "DOCKER_TO_PID[$container]" ]]; then
            DOCKER_PID="${DOCKER_TO_PID[$container]}"
        else
            echo >&2 "WARNING: get_container_pid $container not found in cache"
            exit 1
        fi
    else
        # always get the new PID
        if DOCKER_PID=$(docker inspect -f '{{.State.Pid}}' "$container"); then
            if [ "$DOCKER_PID" -eq 0 ]; then
                echo >&2 "$UTIL: The container $container is not running"
                exit 1
            fi
        else
            echo >&2 "$UTIL: Failed to get the PID of the container"
            exit 1
        fi
    fi

    echo "$DOCKER_PID"
}

# Get a burst size of 10% of throughput over a second.
compute_burstsize() {  # throughput
    local input="$1"
    local numeral=""
    local string=""

    # Extract the numeral part (digits only)
    numeral=$(echo "$input" | grep -oE '[0-9]+')

    # Scale the numerical part to 10%.
    scaled=$((numeral / 10))

    # Extract the string part (non-digits)
    string=$(echo "$input" | grep -oE '[^0-9]+')

    # If necessary, convert the suffix to a suffic allowed by "burst".
    # tc only allows a few suffixes (nothing, *bit, *bps)
    # https://man7.org/linux/man-pages/man8/tc.8.html#PARAMETERS
    # In the first two cases we can keep the suffic, in the last case we need
    # to convert.
    case "$string" in
        *bps)
            # convert bytes per second to bits (the allowed suffix).
            scaled=$((scaled * 8));
            # replace the suffix bps with bit
            string="${string%bps}bit";
            ;;
    esac

    # return the result
    echo "$scaled$string"
}

# create a veth pair and connect two interfaces of two containers
# and configure the throughput and delay
connect_two_interfaces() {

    if (($UID != 0)); then
        echo "$0 needs to be run as root"
        exit 1
    fi

    if [ "$#" -ne 7 ]; then
        echo "Usage: connect_two_interfaces <Container1> <Interface1> <Container2> <Interface2> <Throughput> <Delay> <Buffer>"
        exit 1
    fi

    local container1=$1
    local interface1=$2
    local container2=$3
    local interface2=$4
    local throughput=$5
    local delay=$6
    local buffer=$7

    local burst=$(compute_burstsize "$throughput")

    # generate unique veth interface names
    local identifier="${container1}_${interface1}_${container2}_${interface2}"
    local portname=$(create_unique_port_name "${identifier}")

    local veth_interface1="${portname}_a"
    local veth_interface2="${portname}_b"

    # get the PID of two containers
    local pid1=$(get_container_pid $container1 "False")
    local pid2=$(get_container_pid $container2 "False")

    # create a symlink to use ip netns
    create_netns_symlink $pid1
    create_netns_symlink $pid2

    # create a veth pair
    ip link add $veth_interface1 type veth peer name $veth_interface2

    # set up the interfaces on containers
    ip link set $veth_interface1 netns $pid1
    ip netns exec $pid1 ip link set dev $veth_interface1 name $interface1
    ip netns exec $pid1 ip link set $interface1 up

    ip link set $veth_interface2 netns $pid2
    ip netns exec $pid2 ip link set dev $veth_interface2 name $interface2
    ip netns exec $pid2 ip link set $interface2 up

    # configure the thoughput on both interfaces with tc

    # 1
    ip netns exec $pid1 tc qdisc add dev $interface1 root handle 1:0 netem delay $delay
    ip netns exec $pid1 tc qdisc add dev $interface1 parent 1:1 handle 10: tbf rate \
        "${throughput}" burst $burst latency "${buffer}"

    # 2
    ip netns exec $pid2 tc qdisc add dev $interface2 root handle 1:0 netem delay $delay
    ip netns exec $pid2 tc qdisc add dev $interface2 parent 1:1 handle 10: tbf rate \
        "${throughput}" burst $burst latency "${buffer}"

    # reutrn the new pids
    echo "$pid1 $pid2"
}

# create a veth pair between a service container and a group container
# the throughput and delay is not configured
# If ClientGroup != -1, add a default route to the service container (see
# below), needed for MATRIX and MEASUREMENT to reach each group;
# Otherwise, assume that both containers are services.
# We need a metric value for the default route and use ClientGroup for that,
# so each group must have a unique ClientGroup value (which it should).
# for this interface. We add
connect_service_interfaces() {

    if (($UID != 0)); then
        echo "$0 needs to be run as root"
        exit 1
    fi

    if [ "$#" -ne 7 ]; then
        echo "Usage: connect_service_interfaces <ServiceContainer> <ServiceInterface> <ServiceSubnet> " \
            "<ClientContainer> <ClientInterface> <ClientSubnet> <ClientGroup>"
        exit 1
    fi

    local service_container=$1
    local service_interface=$2
    local service_subnet=$3
    local client_container=$4
    local client_interface=$5
    local client_subnet=$6
    local client_group=$7

    # generate unique veth interface names
    local identifier="${service_container}_${service_interface}_${client_container}_${client_interface}"
    local portname=$(create_unique_port_name "${identifier}")

    local veth_service="${portname}_a"
    local veth_client="${portname}_b"

    # get the PID of two containers
    local pid_service=$(get_container_pid $service_container "False")
    local pid_client=$(get_container_pid $client_container "False")

    # create a symlink to use ip netns
    create_netns_symlink $pid_service
    create_netns_symlink $pid_client

    # create a veth pair
    ip link add $veth_service type veth peer name $veth_client

    # set up the interfaces on containers
    ip link set $veth_service netns $pid_service
    ip netns exec $pid_service ip link set dev $veth_service name $service_interface
    ip netns exec $pid_service ip link set $service_interface up

    ip link set $veth_client netns $pid_client
    ip netns exec $pid_client ip link set dev $veth_client name $client_interface
    ip netns exec $pid_client ip link set $client_interface up

    # add the address
    ip netns exec $pid_service ip addr add $service_subnet dev $service_interface
    # Do not configure the client IP address if the client is a host; the
    # router configuration will do this later. But if client is also a service
    # we need to do it now.
    if [ "$client_group" == "-1" ]; then
        ip netns exec $pid_client ip addr add $client_subnet dev $client_interface
    fi

    # configure static route to each group if group_subnet is not -1
    # Different metrics are needed to add multiple default groups.
    if [ "$client_group" != "-1" ]; then
        ip netns exec $pid_service ip route add default via ${client_subnet%/*} metric $client_group
    fi
}

# connect one pair of L3 host and router
# TODO: also use the general function connect_two_interfaces and configure latency
connect_one_l3_host_router() {

    if (($UID != 0)); then
        echo "$0 needs to be run as root"
        exit 1
    fi

    # check enough arguments are provided
    if [ "$#" -ne 3 ]; then
        echo "Usage: connect_one_l3_host_router <AS> <Region> <HostSuffix>"
        exit 1
    fi

    local CurrentAS=$1
    local CurrentRegion=$2
    local CurrentHostSuffix=$3
    local HostCtnName="${CurrentAS}_${CurrentRegion}host${CurrentHostSuffix}"
    local HostInterface="${CurrentRegion}router"
    local RouterCtnName="${CurrentAS}_${CurrentRegion}router"
    local RouterInterface="host${CurrentHostSuffix}"

    # generate unique veth interface names for the host and the router
    local Identifier="${HostCtnName}_${HostInterface}"
    local PortName
    PortName=$(create_unique_port_name "${Identifier}")

    local HostCtnVethInterface="${PortName}_h"
    local RouterCtnVethInterface="${PortName}_r"

    # get the PID of the host and the router container
    local HostPID
    HostPID=$(get_container_pid "$HostCtnName" "False")
    local RouterPID
    RouterPID=$(get_container_pid "$RouterCtnName" "False")

    # create a symlink to use ip netns
    create_netns_symlink "$HostPID"
    create_netns_symlink "$RouterPID"

    # create a veth pair between the host and the router containers directly
    ip link add $HostCtnVethInterface type veth peer name $RouterCtnVethInterface

    # set up the interfaces on the host container
    ip link set $HostCtnVethInterface netns $HostPID
    ip netns exec $HostPID ip link set dev $HostCtnVethInterface name "$HostInterface"
    ip netns exec $HostPID ip link set $HostInterface up

    # remove default gateway on host and router if it exists
    # otherwise cannot config the new default gateway
    HasDefault=$(ip netns exec $HostPID ip route | grep default || true)
    if [ -n "$HasDefault" ]; then
        ip netns exec $HostPID ip route del default
    fi
    HasDefault=$(ip netns exec $RouterPID ip route | grep default || true)
    if [ -n "$HasDefault" ]; then
        ip netns exec $RouterPID ip route del default
    fi
    # ip netns exec $HostPID ip route del default || true

    # set up the interfaces on the router container
    ip link set $RouterCtnVethInterface netns $RouterPID
    ip netns exec $RouterPID ip link set dev $RouterCtnVethInterface name $RouterInterface
    ip netns exec $RouterPID ip link set $RouterInterface up

    # reuturn the PIDs and interfaces of the host and the router
    echo "$HostPID $RouterPID $HostInterface $RouterInterface"

}

# connect one pair of L2 switches and configure link throughput and delay
connect_one_l2_switch() {

    if (($UID != 0)); then
        echo "$0 needs to be run as root"
        exit 1
    fi

    # check enough arguments are provided
    if [ "$#" -ne 8 ]; then
        echo "Usage: connect_one_l2_switch <AS> <DC1> <SW1> <DC2> <SW2> <Throughput> <Delay> <Buffer>"
        exit 1
    fi

    local CurrentAS=$1
    local CurrentDC1=$2
    local CurrentSW1=$3
    local CurrentDC2=$4
    local CurrentSW2=$5
    local CurrentThroughput=$6
    local CurrentDelay=$7
    local CurrentBuffer=$8

    local SwCtnName1="${CurrentAS}_L2_${CurrentDC1}_${CurrentSW1}"
    local SwCtnName2="${CurrentAS}_L2_${CurrentDC2}_${CurrentSW2}"
    local SwInterface1="${CurrentAS}-${CurrentSW2}"
    local SwInterface2="${CurrentAS}-${CurrentSW1}"

    # connect two interfaces
    connect_two_interfaces $SwCtnName1 $SwInterface1 $SwCtnName2 \
        $SwInterface2 $CurrentThroughput $CurrentDelay $CurrentBuffer \
        > /dev/null

    # configure ports on the switch containers
    docker exec -d "${SwCtnName1}" ovs-vsctl add-port br0 "${SwInterface1}" -- set Port "${SwInterface1}" trunks=0
    docker exec -d "${SwCtnName2}" ovs-vsctl add-port br0 "${SwInterface2}" -- set Port "${SwInterface2}" trunks=0
}

# connect a L2 host to the switch and configure the throughput and delay
connect_one_l2_host() {

    if (($UID != 0)); then
        echo "$0 needs to be run as root"
        exit 1
    fi

    # check enough arguments are provided
    if [ "$#" -ne 7 ]; then
        echo "Usage: connect_one_l2_host <AS> <DC> <SW> <Host> <Throughput> <Delay> <Buffer>"
        exit 1
    fi

    local CurrentAS=$1
    local CurrentDC=$2
    local CurrentSW=$3
    local CurrentHost=$4
    local CurrentThroughput=$5
    local CurrentDelay=$6
    local CurrentBuffer=$7

    local SwitchCtnName="${CurrentAS}_L2_${CurrentDC}_${CurrentSW}"
    local SwitchInterface="${CurrentAS}-${CurrentHost}"

    # host is not a vpn
    if [[ ! $CurrentHost == vpn* ]]; then
        # FIXME: not sure whether I understand correctly
        # assume add_vpn.sh has been run
        # local SwCtnPid=$(get_container_pid "${SwitchCtnName}")
        # local SwitchInterface="${CurrentAS}-${CurrentHost}"   # the interface on the switch
        # local VirtualInterface="g${CurrentAS}_${CurrentHost}" # the virtual interface
        # local TapInterface="tap_g${CurrentAS}_${CurrentHost}" # the tap interface on the server

        # ip link add $SwitchInterface type veth peer name $VirtualInterface # connect the switch and the virtual interface
        # ip link set dev $VirtualInterface up
        # ip link set dev $TapInterface up  # FIXME: device not found

        # # add port on the switch container
        # create_netns_symlink $SwCtnPid
        # ip link set $SwitchInterface netns $SwCtnPid
        # ip netns exec $SwCtnPid ip link set dev $SwitchInterface up

        # # configure ports on the switch container
        # # can only be done after the interface is added to the container
        # docker exec -d "${SwitchCtnName}" ovs-vsctl add-port br0 "${SwitchInterface}"

        # # connect to the ovs bridge, which has been created by vpn_config.sh
        # local BridgeName="vpnbr_${CurrentAS}_${CurrentHost}"
        # ovs-vsctl add-port $BridgeName $VirtualInterface
        # ovs-vsctl add-port $BridgeName $TapInterface
        # # configure the throughput and delay
        # ovs-vsctl set interface $TapInterface ingress_policing_rate="${CurrentThroughput}"
        # tc qdisc add dev $TapInterface root netem delay $CurrentDelay

        # echo "VPN not supported yet"
        # continue

        local HostCtnName="${CurrentAS}_L2_${CurrentDC}_${CurrentHost}"
        local HostInterface="${CurrentAS}-${CurrentSW}"

        # connect two interfaces
        read -r HostPID SwitchPID < <(connect_two_interfaces $HostCtnName $HostInterface $SwitchCtnName \
                $SwitchInterface $CurrentThroughput \
                $CurrentDelay $CurrentBuffer)

        # configure port on the switch container
        # if the link is reconnected, the port is still there, so add a duplicate port will fail
        docker exec -d "${SwitchCtnName}" ovs-vsctl add-port br0 "${SwitchInterface}"
    fi

    # return the host and switch interface names and pids
    echo "$HostInterface $HostPID $SwitchInterface $SwitchPID"

}

# connect a L2 gateway to the switch and configure the throughput and delay
connect_one_l2_gateway() {

    if (($UID != 0)); then
        echo "$0 needs to be run as root"
        exit 1
    fi

    # check enough arguments are provided
    if [ "$#" -ne 7 ]; then
        echo "Usage: connect_one_l2_gateway <AS> <DC> <SW> <Router> <Throughput> <Delay> <Buffer>"
        exit 1
    fi

    local CurrentAS=$1
    local CurrentDC=$2
    local CurrentSW=$3
    local CurrentRouter=$4
    local CurrentThroughput=$5
    local CurrentDelay=$6
    local CurrentBuffer=$7

    local SwitchCtnName="${CurrentAS}_L2_${CurrentDC}_${CurrentSW}"
    local SwitchInterface="${CurrentRouter}router"
    local RouterCtnName="${CurrentAS}_${CurrentRouter}router"
    local RouterInterface="${CurrentRouter}-L2"

    # connect two interfaces
    connect_two_interfaces $SwitchCtnName $SwitchInterface $RouterCtnName \
        $RouterInterface $CurrentThroughput $CurrentDelay $CurrentBuffer \
        > /dev/null

    # configure port on the switch container
    docker exec -d "${SwitchCtnName}" ovs-vsctl add-port br0 "${SwitchInterface}"

}

# connect one pair of internal routers and configure link throughput and delay
connect_one_internal_routers() {

    if (($UID != 0)); then
        echo "$0 needs to be run as root"
        exit 1
    fi

    # check enough arguments are provided
    if [ "$#" -ne 6 ]; then
        echo "Usage: connect_one_internal_routers <AS> <RegionA> <RegionB> <Throughput> <Delay> <Buffer> <Buffer>"
        exit 1
    fi

    local CurrentAS=$1
    local CurrentRA=$2
    local CurrentRB=$3
    local CurrentThroughput=$4
    local CurrentDelay=$5
    local CurrentBuffer=$6

    local RegionACtnName="${CurrentAS}_${CurrentRA}router"
    local RegionAInterface="port_${CurrentRB}"
    local RegionBCtnName="${CurrentAS}_${CurrentRB}router"
    local RegionBInterface="port_${CurrentRA}"

    # connect two interfaces
    connect_two_interfaces $RegionACtnName $RegionAInterface $RegionBCtnName \
        $RegionBInterface $CurrentThroughput $CurrentDelay $CurrentBuffer \
        > /dev/null
}

# connect one pair of external routers and configure link throughput and delay
connect_one_external_routers() {

    if (($UID != 0)); then
        echo "$0 needs to be run as root"
        exit 1
    fi

    # check enough arguments are provided
    if [ "$#" -ne 7 ]; then
        echo "Usage: connect_one_external_routers <AS1> <Region1> <AS2> <Region2> <Throughput> <Delay> <Buffer>"
        exit 1
    fi

    local CurrentAS1=$1
    local CurrentRegion1=$2
    local CurrentAS2=$3
    local CurrentRegion2=$4
    local CurrentThroughput=$5
    local CurrentDelay=$6
    local CurrentBuffer=$7

    # check there is at most 1 IXP
    if [ "$CurrentRegion1" = "IXP" ] && [ "$CurrentRegion2" = "IXP" ]; then
        echo "At most one group can be IXP"
        exit 1
    fi

    # if the group type is IXP, the container name is ASN_IXP
    if [ "$CurrentRegion1" = "IXP" ]; then
        local CtnName1="${CurrentAS1}_IXP"
    else
        local CtnName1="${CurrentAS1}_${CurrentRegion1}router"
    fi

    if [ "$CurrentRegion2" = "IXP" ]; then
        local CtnName2="${CurrentAS2}_IXP"
    else
        local CtnName2="${CurrentAS2}_${CurrentRegion2}router"
    fi

    # if group a is IXP, the interface name on group b is ixp_ASA
    # if group a is AS, the interface name on group b is ext_ASA_Region1
    if [ "$CurrentRegion1" = "IXP" ]; then
        local CtnInterface1="grp_${CurrentAS2}"
        local CtnInterface2="ixp_${CurrentAS1}"
    elif [ "$CurrentRegion2" = "IXP" ]; then
        local CtnInterface2="grp_${CurrentAS1}"
        local CtnInterface1="ixp_${CurrentAS2}"
    else
        local CtnInterface1="ext_${CurrentAS2}_${CurrentRegion2}"
        local CtnInterface2="ext_${CurrentAS1}_${CurrentRegion1}"
    fi

    # connect two interfaces
    connect_two_interfaces $CtnName1 $CtnInterface1 $CtnName2 $CtnInterface2 \
        $CurrentThroughput $CurrentDelay $CurrentBuffer > /dev/null
}

connect_one_measurement() {

    if (($UID != 0)); then
        echo "$0 needs to be run as root"
        exit 1
    fi

    # check enough arguments are provided
    if [ "$#" -ne 2 ]; then
        echo "Usage: connect_one_measurement <AS> <Region>"
        exit 1
    fi

    local CurrentAS=$1
    local CurrentRegion=$2

    local MeasurementCtnName="MEASUREMENT"
    local GroupCtnName="${CurrentAS}_${CurrentRegion}router"
    local MeasurementIntf="group${CurrentAS}"  # No space to match DNS entry.
    local GroupIntf="measurement_${CurrentAS}"
    local MeasurementSubnet="$(subnet_router_MEASUREMENT ${CurrentAS} "measurement")"
    local GroupSubnet="$(subnet_router_MEASUREMENT ${CurrentAS} "group")"

    connect_service_interfaces \
        $MeasurementCtnName $MeasurementIntf $MeasurementSubnet \
        $GroupCtnName $GroupIntf $GroupSubnet $CurrentAS

}

connect_one_ssh_measurement() {

    if (($UID != 0)); then
        echo "$0 needs to be run as root"
        exit 1
    fi

    # check enough arguments are provided
    if [ "$#" -ne 2 ]; then
        echo "Usage: connect_one_ssh_measurement <AS> <Public Key>"
        exit 1
    fi

    local CurrentAS=$1
    local Public_Key=$2
    local MeasurementCtnName="MEASUREMENT"
    local SSHSubnet="$(subnet_sshContainer_groupContainer ${CurrentAS} -1 -1 "MEASUREMENT")"
    local BridgeName="${CurrentAS}_ssh"
    local sshifname="ssh_group${CurrentAS}"

    docker network connect --ip="${SSHSubnet%/*}" "${BridgeName}" "${MeasurementCtnName}" > /dev/null

    # Find name of new interface and rename it.
    local ifname=$(docker exec "${MeasurementCtnName}" ip -oneline addr show | grep "${SSHSubnet%/*}" | cut -f 2 -d ' ')

    docker exec "${MeasurementCtnName}" ip link set dev "${ifname}" down
    docker exec "${MeasurementCtnName}" \
    ip link set dev "${ifname}" name "${sshifname}"
    docker exec "${MeasurementCtnName}" ip link set dev "${sshifname}" up

    # Append public key
    docker exec -d "${MeasurementCtnName}" \
        bash -c "echo $Public_Key >> /root/.ssh/authorized_keys"
}

connect_one_matrix() {

    if (($UID != 0)); then
        echo "$0 needs to be run as root"
        exit 1
    fi

    # check enough arguments are provided
    if [ "$#" -ne 2 ]; then
        echo "Usage: connect_one_matrix <AS> <Region>"
        exit 1
    fi

    local CurrentAS=$1
    local CurrentRegion=$2

    local MatrixCtnName="MATRIX"
    local GroupCtnName="${CurrentAS}_${CurrentRegion}router"
    local MatrixIntf="group_${CurrentAS}"
    local GroupIntf="matrix_${CurrentAS}"
    local MatrixSubnet="$(subnet_router_MATRIX ${CurrentAS} "matrix")"
    local GroupSubnet="$(subnet_router_MATRIX ${CurrentAS} "group")"

    connect_service_interfaces \
        $MatrixCtnName $MatrixIntf $MatrixSubnet \
        $GroupCtnName $GroupIntf $GroupSubnet $CurrentAS

}

connect_one_dns() {

    if (($UID != 0)); then
        echo "$0 needs to be run as root"
        exit 1
    fi

    # check enough arguments are provided
    if [ "$#" -ne 2 ]; then
        echo "Usage: connect_one_dns <AS> <Region>"
        exit 1
    fi

    local CurrentAS=$1
    local CurrentRegion=$2

    local DNSCtnName="DNS"
    local GroupCtnName="${CurrentAS}_${CurrentRegion}router"
    local DNSIntf="group_${CurrentAS}"
    local GroupIntf="dns_${CurrentAS}"
    local DNSSubnet="$(subnet_router_DNS ${CurrentAS} "dns-group")"
    local GroupSubnet="$(subnet_router_DNS ${CurrentAS} "group")"

    connect_service_interfaces \
        $DNSCtnName $DNSIntf $DNSSubnet \
        $GroupCtnName $GroupIntf $GroupSubnet $CurrentAS

}
