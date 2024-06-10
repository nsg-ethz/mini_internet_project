#!/bin/bash
#
# Restart the container and reconnect the link

# sanity check
trap 'exit 1' ERR
set -o errexit
set -o pipefail
set -o nounset

# make sure the script is executed with root privileges
if (($UID != 0)); then
    echo "$0 needs to be run as root"
    exit 1
fi

# make sure the script is only executed in the platform/ directory
if [[ ! $(basename "$PWD") == "platform" ]]; then
    echo "Please execute the script in the platform/ directory"
    exit 1
fi

DIRECTORY=$(pwd)
source "${DIRECTORY}"/config/variables.sh
source "${DIRECTORY}"/config/subnet_config.sh
source "${DIRECTORY}"/setup/_parallel_helper.sh
source "${DIRECTORY}"/groups/docker_pid.map
source "${DIRECTORY}"/setup/_connect_utils.sh
readarray ASConfig <"${DIRECTORY}"/config/AS_config.txt
GroupNumber=${#ASConfig[@]}

print_usage() {
    echo "Usage: $0 router <AS> <Region>"
    echo "       $0 l3-host <AS> <Region> [host|host[0-9]]"
    echo "       $0 l2-host <AS> <Host>"
    echo "       $0 switch <AS> <Region>"
    echo "       $0 ssh <AS>"
    echo "       $0 ixp <AS>"
    echo "       $0 matrix"
    echo "       $0 dns"
    echo "       $0 measurement"
    echo "       $0 web"
}



# restart an L3 host
restart_one_l3_host() {

    # check enough arguments are provided
    if [ "$#" -ne 3 ]; then
        echo "Usage: restart_one_l3_host <AS> <Region> [host|host[0-9]]"
        exit 1
    fi

    local CurrentAS=$1
    local CurrentRegion=$2
    local CurrentHostName=$3
    local HasConfig=$(has_config "${CurrentAS}")

    local IsKrill=$(is_krill_or_routinator "${CurrentAS}" "${CurrentHostName}" "{CurrentRegion}" "krill")
    local IsRoutinator=$(is_krill_or_routinator "${CurrentAS}" "${CurrentRegion}" "{CurrentHostName}" "routinator")

    local HostSuffix=$(echo "${CurrentHostName}" | sed 's/host//')
    local HostCtnName="${CurrentAS}_${CurrentRegion}host${HostSuffix}"
    local RouterCtnName="${CurrentAS}_${CurrentRegion}router"

    # make sure the container is not running, otherwise will cause error and need to manually clear ip link
    docker kill "${HostCtnName}" 2>/dev/null || true

    # clean up the old netns of the container
    clean_ctn_netns "${HostCtnName}"
    clean_ip_link

    docker restart "${HostCtnName}" 1>/dev/null

    echo "Restarted host ${HostCtnName}"

    read -r HostPID RouterPID HostInterface RouterInterface \
        < <(connect_one_l3_host_router "${CurrentAS}" "${CurrentRegion}" "${HostSuffix}")

    echo "Reconnected host ${HostCtnName} to router ${RouterCtnName}"

    # rename eth0 on host to ssh
    ip netns exec "${HostPID}" ip link set dev eth0 down
    ip netns exec "${HostPID}" ip link set dev eth0 name ssh
    ip netns exec "${HostPID}" ip link set dev ssh up

    echo "Renamed eth0 to ssh on host ${HostCtnName}"

    if [[ "${IsKrill}" == "True" ]]; then
        # rename the krill interface
        # the krill interface  is connect to a docker network,
        # so no need to reconnect it
        ip netns exec "${HostPID}" ip link set dev eth1 down # krill service starts later than the ssh
        ip netns exec "${HostPID}" ip link set dev eth1 name krill
        ip netns exec "${HostPID}" ip link set dev krill up

        echo "Renamed eth1 to krill on host ${HostCtnName}"
    fi

    if [[ "${IsRoutinator}" == "True" ]]; then
        # upate the routinator
        docker exec "${HostCtnName}" routinator update
        echo "Updated routinator on host ${HostCtnName}"
    fi

    local IsAllInOne=$(is_all_in_one "${CurrentAS}")

    if [[ "${HasConfig}" == "True" ]]; then
        if [[ "${IsAllInOne}" == "False" ]]; then
            local RegionID=$(get_region_id "${CurrentAS}" "${CurrentRegion}")
            RouterSubnet="$(subnet_host_router "${CurrentAS}" "${RegionID}" "router")"
            HostSubnet="$(subnet_host_router "${CurrentAS}" "${RegionID}" "host")"
        else
            RouterSubnet="$(subnet_host_router "${CurrentAS}" "${HostSuffix}" "router")"
            HostSubnet="$(subnet_host_router "${CurrentAS}" "${HostSuffix}" "host")"
        fi

        # add the interface address and the default gateway on the host
        ip netns exec $HostPID ip addr add $HostSubnet dev $HostInterface
        ip netns exec $HostPID ip route add default via ${RouterSubnet%/*}

        echo "Configured host ${HostCtnName}"
    fi

}

# restart one router
restart_one_router() {

    # check enough arguments are provided
    if [ "$#" -ne 2 ]; then
        echo "Usage: restart_one_router <AS> <Region>"
        exit 1
    fi

    local CurrentAS=$1
    local CurrentRegion=$2
    local HasConfig=$(has_config "${CurrentAS}")

    local RouterCtnName="${CurrentAS}_${CurrentRegion}router"

    docker kill "${RouterCtnName}" 2>/dev/null || true

    # clean up the old netns of the container
    clean_ctn_netns "${RouterCtnName}"
    clean_ip_link

    docker restart "${RouterCtnName}" 1>/dev/null

    echo "Restarted router ${RouterCtnName}"

    # get the config file for the current AS
    for ((k = 0; k < GroupNumber; k++)); do
        GroupK=(${ASConfig[$k]})               # group config file array
        GroupAS="${GroupK[0]}"                 # ASN
        GroupRouterConfig="${GroupK[3]}"       # L3 router config file
        GroupInternalLinkConfig="${GroupK[4]}" # Group internal link config file
        GroupL2SwitchConfig="${GroupK[5]}"     # l2 switch config file
        GroupL2HostConfig="${GroupK[6]}"       # l2 host config file

        if [[ "${GroupAS}" == "${CurrentAS}" ]]; then

            readarray Routers <"${DIRECTORY}/config/$GroupRouterConfig"
            readarray InternalLinks <"${DIRECTORY}/config/$GroupInternalLinkConfig"
            readarray L2Switches <"${DIRECTORY}/config/$GroupL2SwitchConfig"
            readarray L2Hosts <"${DIRECTORY}/config/$GroupL2HostConfig"

            RouterNumber=${#Routers[@]}
            InternalLinkNumber=${#InternalLinks[@]}
            L2SwitchNumber=${#L2Switches[@]}
            L2HostNumber=${#L2Hosts[@]}
            break
        fi
    done

    # add the link between the router and the l3 host
    for ((i = 0; i < RouterNumber; i++)); do
        RouterI=(${Routers[$i]})
        RouterRegion="${RouterI[0]}"
        HostImage="${RouterI[2]}"

        if [[ ${RouterRegion} == "${CurrentRegion}" ]]; then

            HostSuffix=""
            if [[ ${#RouterI[@]} -gt 4 && "${RouterI[4]}" == "ALL" && "${HostImage}" != "N/A" ]]; then
                HostSuffix="${i}"
            fi
            local HostCtnName="${CurrentAS}_${CurrentRegion}host${HostSuffix}"

            if [[ "${HostImage}" != "N/A" ]]; then

                read -r HostPID RouterPID HostInterface RouterInterface \
                    < <(connect_one_l3_host_router "${CurrentAS}" "${RouterRegion}" "${HostSuffix}")

                echo "Reconnected router ${RouterCtnName} to host ${HostCtnName}"

                if [[ "${HasConfig}" == "True" ]]; then
                    local IsAllInOne=$(is_all_in_one "${CurrentAS}")
                    # configure the connected host
                    if [[ "${IsAllInOne}" == "False" ]]; then
                        local RegionID=$(get_region_id "${CurrentAS}" "${CurrentRegion}")
                        RouterSubnet="$(subnet_host_router "${CurrentAS}" "${RegionID}" "router")"
                        HostSubnet="$(subnet_host_router "${CurrentAS}" "${RegionID}" "host")"
                    else
                        RouterSubnet="$(subnet_host_router "${CurrentAS}" "${HostSuffix}" "router")"
                        HostSubnet="$(subnet_host_router "${CurrentAS}" "${HostSuffix}" "host")"
                    fi

                    # add the interface address and the default gateway on the host
                    ip netns exec $HostPID ip addr add $HostSubnet dev $HostInterface
                    ip netns exec $HostPID ip route add default via ${RouterSubnet%/*}

                    echo "Configured host ${HostCtnName}"
                fi
            fi

        fi
    done

    # get the unique VLAN set used in the L2
    local VlanSet
    IFS=' ' read -r -a VlanSet <<<"$(get_unique_vlan_set "${CurrentAS}")"
    # map from the DCName to the DCId
    declare -A DCNameToId
    while read -r DCName DCId; do
        DCNameToId["$DCName"]="$DCId"
    done < <(get_dc_name_to_id "${CurrentAS}")

    # map from the L2 gateway router to the DC Id
    declare -A RouterToDCId
    for ((i = 0; i < L2SwitchNumber; i++)); do
        L2SwitchI=(${L2Switches[$i]}) # L2 switch row
        DCName="${L2SwitchI[0]}"      # DC name
        SWName="${L2SwitchI[1]}"      # switch name
        RouterName="${L2SwitchI[2]}"  # gateway router name
        Throughput=$DEFAULT_THROUGHPUT
        Delay=$DEFAULT_DELAY
        Buffer=$DEFAULT_BUFFER

        if [[ "${RouterName}" == "${CurrentRegion}" ]]; then
            connect_one_l2_gateway "${CurrentAS}" "${DCName}" "${SWName}" \
                "${RouterName}" "${Throughput}" "${Delay}" "${Buffer}" > /dev/null
            echo "Reconnected l2 switch ${SWName} to router ${RouterName} in ${CurrentAS}"
        fi

        # record the L2 gateway router and the corresponding DC id
        if [[ -z "${RouterToDCId[$RouterName]+_}" ]]; then
            RouterToDCId[$RouterName]="${DCNameToId[$DCName]}"
        fi
    done

    # configure the tunnel and vlan
    local RouterPID=$(get_container_pid "${RouterCtnName}" "False")
    create_netns_symlink "${RouterPID}"
    read TunnelEndA TunnelEndB <"${DIRECTORY}/config/l2_tunnel.txt"
    for RouterName in "${!RouterToDCId[@]}"; do
        DCId="${RouterToDCId[$RouterName]}"
        # if the current router is the gateway router
        if [[ "${RouterName}" == "${CurrentRegion}" ]]; then
            # configure VLAN interfaces
            RegionId=$(get_region_id "${CurrentAS}" "${CurrentRegion}")
            for ((j = 0; j < ${#VlanSet[@]}; j++)); do
                VlanTag="${VlanSet[$j]}"
                RouterInterface="${CurrentRegion}-L2.$VlanTag"
                ip netns exec "${RouterPID}" ip link add link "${RouterInterface%.*}" name "${RouterInterface}" type vlan id "${VlanTag}"
            done
            echo "Set up VLAN interfaces on router ${RouterCtnName}"

            # if the current router is one end of the tunnel
            # if the tunnel was set before, the tunnel is gone after restarting the container, but the sit0 interface is kept
            # once a tunnel is set, the sit0 will be displayed on the server and all container!
            if [[ "${HasConfig}" == "True" ]]; then
                if [[ "${RouterName}" == "${TunnelEndA}" ]] || [[ "${RouterName}" == "${TunnelEndB}" ]]; then
                    # configure the 6in4 tunnel
                    EndAId=$(get_region_id "${CurrentAS}" "${TunnelEndA}")
                    EndBId=$(get_region_id "${CurrentAS}" "${TunnelEndB}")
                    if [[ "${RouterName}" == "${TunnelEndA}" ]]; then
                        RemoteSubnet=$(subnet_router "${CurrentAS}" "${EndBId}")
                        LocalSubnet=$(subnet_router "${CurrentAS}" "${EndAId}")
                    elif [[ "${RouterName}" == "${TunnelEndB}" ]]; then
                        RemoteSubnet=$(subnet_router "${CurrentAS}" "${EndAId}")
                        LocalSubnet=$(subnet_router "${CurrentAS}" "${EndBId}")
                    fi
                    TunnelName="tun6to4_${CurrentAS}"
                    docker exec -d "${RouterCtnName}" ip tunnel add "${TunnelName}" mode sit remote "${RemoteSubnet%/*}" local "${LocalSubnet%/*}" ttl 255
                    docker exec -d "${RouterCtnName}" ip link set "${TunnelName}" up
                    # get the destination of the other end of the tunnel
                    if [[ "${RouterName}" == "${TunnelEndA}" ]]; then
                        OtherDCId="${RouterToDCId[${TunnelEndB}]}"
                    elif [[ "${RouterName}" == "${TunnelEndB}" ]]; then
                        OtherDCId="${RouterToDCId[${TunnelEndA}]}"
                    fi
                    # add ipv6 static route
                    for ((j = 0; j < ${#VlanSet[@]}; j++)); do
                        VlanTag="${VlanSet[$j]}"
                        SubnetV6Vlan=$(subnet_l2_ipv6 "${CurrentAS}" "${OtherDCId}" "${VlanTag}" 0)
                        docker exec -d "${RouterCtnName}" ip route add "${SubnetV6Vlan}" dev "${TunnelName}"
                    done
                    echo "Configured 6in4 tunnel on router ${RouterCtnName}"
                fi
            fi
        fi
    done

    # add the internal link
    for ((i = 0; i < InternalLinkNumber; i++)); do
        InternalLinkI=(${InternalLinks[$i]}) # internal link row
        RegionA="${InternalLinkI[0]}"        # region A
        RegionB="${InternalLinkI[1]}"        # region B
        Throughput="${InternalLinkI[2]}"     # throughput
        Delay="${InternalLinkI[3]}"          # delay
        Buffer="${InternalLinkI[4]}"         # buffer latency (in ms)

        if [[ "${RegionA}" == "${CurrentRegion}" ]] || [[ "${RegionB}" == "${CurrentRegion}" ]]; then
            connect_one_internal_routers "${CurrentAS}" "${RegionA}" "${RegionB}" "${Throughput}" "${Delay}" "${Buffer}"
            echo "Reconnected router ${RegionA} and router ${RegionB} in ${CurrentAS}"
        fi

    done

    # add the external link
    readarray ExternalLinks <"${DIRECTORY}/config/aslevel_links.txt"
    ExternalLinkNumber=${#ExternalLinks[@]}

    for ((i = 0; i < ExternalLinkNumber; i++)); do
        LinkI=(${ExternalLinks[$i]}) # external link row
        AS1="${LinkI[0]}"            # AS1
        Region1="${LinkI[1]}"        # region 1 in AS1
        AS2="${LinkI[3]}"            # AS2
        Region2="${LinkI[4]}"        # region 2 in AS2
        Throughput="${LinkI[6]}"     # throughput
        Delay="${LinkI[7]}"          # delay
        Buffer="${LinkI[8]}"         # buffer latency (in ms)

        # rename region None with IXP
        if [[ "${Region1}" == "None" ]]; then
            Region1="IXP"
        fi
        if [[ "${Region2}" == "None" ]]; then
            Region2="IXP"
        fi

        if [[ "${AS1}" == "${CurrentAS}" ]] && [[ "${Region1}" == "${CurrentRegion}" ]]; then
            connect_one_external_routers "${AS1}" "${Region1}" "${AS2}" "${Region2}" "${Throughput}" "${Delay}" "${Buffer}"
            echo "Reconnected external link between ${Region1} in ${AS1} and ${Region2} in ${AS2}"
        fi
        if [[ "${AS2}" == "${CurrentAS}" ]] && [[ "${Region2}" == "${CurrentRegion}" ]]; then
            connect_one_external_routers "${AS1}" "${Region1}" "${AS2}" "${Region2}" "${Throughput}" "${Delay}" "${Buffer}"
            echo "Reconnected external link between ${Region1} in ${AS1} and ${Region2} in ${AS2}"
        fi

    done

    # add the service link
    for ((i = 0; i < RouterNumber; i++)); do
        RouterI=(${Routers[$i]})      # router config file array
        RouterRegion="${RouterI[0]}"  # region name
        RouterService="${RouterI[1]}" # measurement/matrix/dns

        if [[ "${RouterRegion}" == "${CurrentRegion}" ]]; then
            # connect the measurement container to each group
            if [[ "$RouterService" == "MEASUREMENT" ]]; then
                connect_one_measurement "${CurrentAS}" "${RouterRegion}"
                echo "Reconnected MEASUREMENT to ${RouterRegion} in ${CurrentAS}"
            fi

            # connect the matrix container to each group
            if [[ "$RouterService" == "MATRIX" ]]; then
                connect_one_matrix "${CurrentAS}" "${RouterRegion}"
                echo "Reconnected MATRIX to ${RouterRegion} in ${CurrentAS}"
            fi

            # # connect the dns container to each group
            if [[ "$RouterService" == "DNS" ]]; then
                connect_one_dns "${CurrentAS}" "${RouterRegion}"
                echo "Reconnected DNS to ${RouterRegion} in ${CurrentAS}"
            fi
        fi
    done

    # rename eth0 on the router to ssh
    # this cannot be done first because need to call create the symlink before
    ip netns exec "${RouterPID}" ip link set dev eth0 down
    ip netns exec "${RouterPID}" ip link set dev eth0 name ssh
    ip netns exec "${RouterPID}" ip link set dev ssh up

    echo "Renamed eth0 to ssh on router ${RouterCtnName}"

    # reset rpki and clear ip bgp
    # maybe still need to clear and reset manually, as the bgp takes time to converge
    sleep 60
    docker exec "${RouterCtnName}" vtysh -c 'clear ip bgp *' -c 'exit'
    docker exec "${RouterCtnName}" vtysh -c 'conf t' -c 'rpki' -c 'rpki reset' -c 'exit' -c 'exit'
    echo "Reset RPKI and BGP on router ${RouterCtnName}"

}

# restart an L2 host
restart_one_l2_host() {

    # check enough arguments are provided
    if [ "$#" -ne 2 ]; then
        echo "Usage: restart_one_l2_host <AS> <HostName>"
        exit 1
    fi

    local CurrentAS=$1
    local CurrentHostName=$2
    local HasConfig=$(has_config "${CurrentAS}")

    # get the connected switch and the host container name
    for ((k = 0; k < GroupNumber; k++)); do
        GroupK=(${ASConfig[$k]})         # group config file array
        GroupAS="${GroupK[0]}"           # ASN
        GroupRouterConfig="${GroupK[3]}" # used to compute the starting id of a L2 host
        GroupL2HostConfig="${GroupK[6]}" # l2 host config file

        if [[ "${GroupAS}" == "${CurrentAS}" ]]; then

            # map from the DCName to the DCId
            declare -A DCNameToId
            while read -r DCName DCId; do
                DCNameToId["$DCName"]="$DCId"
            done < <(get_dc_name_to_id "${CurrentAS}")

            declare -A HostToVlanId
            while read -r HostName VlanId; do
                HostToVlanId[$HostName]=$VlanId
            done < <(get_l2_host_to_vlan_id "${CurrentAS}")

            readarray L2Hosts <"${DIRECTORY}/config/$GroupL2HostConfig"
            L2HostNumber=${#L2Hosts[@]}
            for ((i = 0; i < L2HostNumber; i++)); do
                L2HostI=(${L2Hosts[$i]})
                HostName="${L2HostI[0]}"
                DCName="${L2HostI[2]}"
                SWName="${L2HostI[3]}"
                Throughput="${L2HostI[4]}"
                Delay="${L2HostI[5]}"
                Buffer="${L2HostI[6]}"
                VlanTag="${L2HostI[7]}"

                # assume the host only appear in one line
                if [[ "${HostName}" == "${CurrentHostName}" ]]; then
                    # TODO: don't hardcode the container name
                    # cannot move the following out of the loop, because need to find the DCName
                    HostCtnName="${CurrentAS}_L2_${DCName}_${HostName}"

                    docker kill "${HostCtnName}" 2>/dev/null || true

                    # clean up the old netns of the container
                    clean_ctn_netns "${HostCtnName}"
                    clean_ip_link

                    docker restart "${HostCtnName}" 1>/dev/null

                    echo "Restarted host ${HostCtnName}"

                    read -r HostInterface HostPID SwitchInterface SwitchPID \
                        < <(connect_one_l2_host "${GroupAS}" "${DCName}" "${SWName}" "${HostName}" "${Throughput}" "${Delay}" "${Buffer}")
                    echo "Reconnected host ${HostName} to switch ${SWName} in ${DCName} in ${GroupAS}"

                    # rename eth0 to ssh
                    ip netns exec $HostPID ip link set dev eth0 down
                    ip netns exec $HostPID ip link set dev eth0 name ssh
                    ip netns exec $HostPID ip link set dev ssh up
                    echo "Renamed eth0 to ssh on host ${HostCtnName}"

                    # remove ipv4 and ipv6 default gateway if exists
                    HasDefault=$(ip netns exec $HostPID ip route | grep default || true)
                    if [ -n "$HasDefault" ]; then
                        ip netns exec $HostPID ip route del default
                    fi
                    HasDefaultV6=$(ip netns exec $HostPID ip -6 route | grep default || true)
                    if [ -n "$HasDefaultV6" ]; then
                        ip netns exec $HostPID ip -6 route del default
                    fi
                    echo "Removed ipv4 and ipv6 default gateway on host ${HostCtnName}"

                    # has config
                    if [[ "${HasConfig}" == "True" ]]; then
                        # get the subnet of the host
                        local HostSubnet=$(subnet_l2 "${GroupAS}" "${DCNameToId[$DCName]}" "${VlanTag}" "${HostToVlanId[$HostName]}")
                        local HostSubnetV6=$(subnet_l2_ipv6 "${GroupAS}" "${DCNameToId[$DCName]}" "${VlanTag}" "${HostToVlanId[$HostName]}")
                        # add the interface address and the default gateway on the host
                        ip netns exec $HostPID ip addr add $HostSubnet dev $HostInterface
                        ip netns exec $HostPID ip -6 addr add $HostSubnetV6 dev $HostInterface

                        # add ipv4 and ipv6 default route
                        local HostGateway=$(subnet_l2 "${GroupAS}" "${DCNameToId[$DCName]}" "${VlanTag}" 1)
                        local HostGatewayV6=$(subnet_l2_ipv6 "${GroupAS}" "${DCNameToId[$DCName]}" "${VlanTag}" 1)
                        ip netns exec $HostPID ip route add default via ${HostGateway%/*}
                        ip netns exec $HostPID ip -6 route add default via ${HostGatewayV6%/*}

                        echo "Configured L2 host ${HostCtnName}"
                    fi

                    break
                fi

            done
            break
        fi
    done

}

# restart an l2 switch
restart_one_l2_switch() {
    # check enough arguments are provided
    if [ "$#" -ne 2 ]; then
        echo "Usage: restart_one_l2_switch <AS> <SwitchName>"
        exit 1
    fi

    local CurrentAS=$1
    local CurrentSwitch=$2
    local HasConfig=$(has_config "${CurrentAS}")

    # get the L2 config file
    for ((k = 0; k < GroupNumber; k++)); do
        GroupK=(${ASConfig[$k]})           # group config file array
        GroupAS="${GroupK[0]}"             # ASN
        GroupL2SwitchConfig="${GroupK[5]}" # l2 switch config file
        GroupL2HostConfig="${GroupK[6]}"   # l2 host config file
        GroupL2LinkConfig="${GroupK[7]}"   # l2 link config file

        if [[ "${GroupAS}" == "${CurrentAS}" ]]; then

            readarray L2Switches <"${DIRECTORY}/config/$GroupL2SwitchConfig"
            readarray L2Hosts <"${DIRECTORY}/config/$GroupL2HostConfig"
            readarray L2Links <"${DIRECTORY}/config/$GroupL2LinkConfig"
            L2SwitchNumber=${#L2Switches[@]}
            L2HostNumber=${#L2Hosts[@]}
            L2LinkNumber=${#L2Links[@]}

            # all ovs-vsctl config is still there, but its connected hosts also need to be reconfigured

            # used to configure connected l2 hosts
            declare -A DCNameToId
            while read -r DCName DCId; do
                DCNameToId["$DCName"]="$DCId"
            done < <(get_dc_name_to_id "${CurrentAS}")

            local VlanSet
            IFS=' ' read -r -a VlanSet <<<"$(get_unique_vlan_set "${CurrentAS}")"

            declare -A HostToVlanId
            while read -r HostName VlanId; do
                HostToVlanId[$HostName]=$VlanId
            done < <(get_l2_host_to_vlan_id "${CurrentAS}")

            # reconnect the switch to the router
            for ((i = 0; i < L2SwitchNumber; i++)); do
                L2SwitchI=(${L2Switches[$i]}) # L2 switch row
                DCName="${L2SwitchI[0]}"      # DC name
                SWName="${L2SwitchI[1]}"      # switch name
                RouterName="${L2SwitchI[2]}"  # gateway router name
                Throughput=$DEFAULT_THROUGHPUT 
                Delay=$DEFAULT_DELAY
                Buffer=$DEFAULT_BUFFER

                if [[ "${SWName}" == "${CurrentSwitch}" ]]; then
                    local SwitchCtnName="${CurrentAS}_L2_${DCName}_${CurrentSwitch}"

                    docker kill "${SwitchCtnName}" 2>/dev/null || true

                    # clean up the old netns of the container
                    clean_ctn_netns "${SwitchCtnName}"
                    clean_ip_link

                    docker restart "${SwitchCtnName}" 1>/dev/null

                    echo "Restarted switch ${SwitchCtnName}"

                    read -r SwitchInterface SwitchPID GatewayInterface GatewayPID \
                        < <(connect_one_l2_gateway "${GroupAS}" "${DCName}" "${SWName}" "${RouterName}" "${Throughput}" "${Delay}" "${Buffer}")
                    echo "Reconnected l2 switch ${SWName} to router ${RouterName} in ${DCName} in ${GroupAS}"

                    # set up the VLAN link on the gateway router
                    GatewayCtnName="${CurrentAS}_${RouterName}router"

                    # TODO: check why the symlink is deleted so early in this case
                    create_netns_symlink "${GatewayPID}"
                    for ((j = 0; j < ${#VlanSet[@]}; j++)); do
                        VlanTag="${VlanSet[$j]}"
                        RouterVlanInterface="${RouterName}-L2.$VlanTag"
                        ip netns exec "${GatewayPID}" ip link add link "${RouterVlanInterface%.*}" name \
                            "${RouterVlanInterface}" type vlan id "${VlanTag}"
                    done
                    echo "Set up VLAN interfaces on ${GatewayCtnName}"

                    # rename eth0 to ssh
                    ip netns exec "${SwitchPID}" ip link set dev eth0 down
                    ip netns exec "${SwitchPID}" ip link set dev eth0 name ssh
                    ip netns exec "${SwitchPID}" ip link set dev ssh up

                    echo "Renamed eth0 to ssh on switch ${SwitchCtnName}"


                    # assume there is at most gateway router for the switch
                    break
                fi
            done

            # reconnect the switch to other switches
            # could also have multiple links or no link
            for ((i = 0; i < L2LinkNumber; i++)); do
                L2LinkI=(${L2Links[$i]})   # L2 link row
                SWNameA="${L2LinkI[1]}"    # switch A name
                SWNameB="${L2LinkI[3]}"    # switch B name
                Throughput="${L2LinkI[4]}" # throughput
                Delay="${L2LinkI[5]}"      # delay
                Buffer="${L2LinkI[6]}"     # buffer latency (in ms)

                if [[ "${SWNameA}" == "${CurrentSwitch}" ]] || [[ "${SWNameB}" == "${CurrentSwitch}" ]]; then
                    connect_one_l2_switch "${GroupAS}" "${DCName}" "${SWNameA}" "${DCName}" "${SWNameB}" "${Throughput}" "${Delay}" "${Buffer}"
                    echo "Reconnected switch ${SWNameA} and switch ${SWNameB} in ${DCName} in ${GroupAS}"

                fi
            done

            # reconnect the switch to the L2 hosts
            # not break because a switch can connect to multiple hosts
            for ((i = 0; i < L2HostNumber; i++)); do
                L2HostI=(${L2Hosts[$i]})   # L2 host row
                HostName="${L2HostI[0]}"   # host name
                DCName="${L2HostI[2]}"     # DC name
                SWName="${L2HostI[3]}"     # switch name
                Throughput="${L2HostI[4]}" # throughput
                Delay="${L2HostI[5]}"      # delay
                Buffer="${L2HostI[6]}"     # buffer latency (in ms)
                VlanTag="${L2HostI[7]}"    # vlan tag

                # assuming the switch at least connects to one host
                # so the SwitchPID is not empty when we exit the loop
                if [[ "${SWName}" == "${CurrentSwitch}" ]]; then

                    read -r HostInterface HostPID SwitchInterface SwitchPID \
                        < <(connect_one_l2_host "${GroupAS}" "${DCName}" "${SWName}" "${HostName}" "${Throughput}" "${Delay}" "${Buffer}")
                    echo "Reconnected host ${HostName} to switch ${SWName} in ${DCName} in ${GroupAS}"

                    if [[ "${HasConfig}" == "True" ]]; then
                        HostCtnName="${CurrentAS}_L2_${DCName}_${HostName}"

                        # get the subnet of the host
                        local HostSubnet=$(subnet_l2 "${GroupAS}" "${DCNameToId[$DCName]}" "${VlanTag}" "${HostToVlanId[$HostName]}")
                        local HostSubnetV6=$(subnet_l2_ipv6 "${GroupAS}" "${DCNameToId[$DCName]}" "${VlanTag}" "${HostToVlanId[$HostName]}")
                        # add the interface address and the default gateway on the host
                        ip netns exec $HostPID ip addr add $HostSubnet dev $HostInterface
                        ip netns exec $HostPID ip -6 addr add $HostSubnetV6 dev $HostInterface

                        # add ipv4 and ipv6 default route
                        local HostGateway=$(subnet_l2 "${GroupAS}" "${DCNameToId[$DCName]}" "${VlanTag}" 1)
                        local HostGatewayV6=$(subnet_l2_ipv6 "${GroupAS}" "${DCNameToId[$DCName]}" "${VlanTag}" 1)
                        ip netns exec $HostPID ip route add default via ${HostGateway%/*}
                        ip netns exec $HostPID ip -6 route add default via ${HostGatewayV6%/*}

                        echo "Configured L2 host ${HostCtnName}"
                    fi

                fi
            done

            break
        fi
    done
}

# restart an ixp
restart_one_ixp() {
    # check enough arguments are provided
    if [ "$#" -ne 1 ]; then
        echo "Usage: reconnect_one_ixp <AS>"
        exit 1
    fi

    local CurrentAS=$1

    local IXPCtnName="${CurrentAS}_IXP"

    docker kill "${IXPCtnName}" 2>/dev/null || true
    # set -x # used to see which router container still has the IXP interface

    # clean up the old netns of the container
    clean_ctn_netns "${IXPCtnName}"
    clean_ip_link

    docker restart "${IXPCtnName}" 1>/dev/null

    echo "Restarted IXP ${IXPCtnName}"

    # need enough time for each router to clean up the old IXP interface
    sleep 300

    # connect all external links
    readarray ExternalLinks <"${DIRECTORY}/config/aslevel_links.txt"
    ExternalLinkNumber=${#ExternalLinks[@]}
    for ((i = 0; i < ExternalLinkNumber; i++)); do
        LinkI=(${ExternalLinks[$i]}) # external link row
        AS1="${LinkI[0]}"            # AS1
        Region1="${LinkI[1]}"        # region 1 in AS1
        AS2="${LinkI[3]}"            # AS2
        Region2="${LinkI[4]}"        # region 2 in AS2
        Throughput="${LinkI[6]}"     # throughput
        Delay="${LinkI[7]}"          # delay
        Buffer="${LinkI[8]}"         # buffer latency (in ms)

        # rename region None with IXP
        if [[ "${Region1}" == "None" ]]; then
            Region1="IXP"
        fi
        if [[ "${Region2}" == "None" ]]; then
            Region2="IXP"
        fi

        # if one AS is the current AS, connect the other AS
        if [[ "${AS1}" == "${CurrentAS}" || "${AS2}" == "${CurrentAS}" ]]; then
            connect_one_external_routers "${AS1}" "${Region1}" "${AS2}" "${Region2}" "${Throughput}" "${Delay}" "${Buffer}"
            echo "Reconnected external link between ${Region1} in ${AS1} and ${Region2} in ${AS2}"
        fi

        # no config is needed for the IXP

    done

    # IXP does not have ssh interface

    # manually load the config as it won't be auto-loaded
    docker exec -d "${IXPCtnName}" bash -c 'vtysh -c "conf t" -c "$(tail -n +2 conf_full.sh)" -c "exit"' &
    docker exec -d "${IXPCtnName}" bash -c "ip addr add $(subnet_router_IXP -1 ${CurrentAS} IXP) dev IXP"
    docker exec -d "${IXPCtnName}" bash -c "ip link set dev IXP up"

    # clear bgp
    docker exec "${IXPCtnName}" vtysh -c 'clear ip bgp *' -c 'exit'
}

# restart an ssh proxy container
restart_one_ssh() {
    # check enough arguments are provided
    if [ "$#" -ne 1 ]; then
        echo "Usage: restart_one_ssh <AS>"
        exit 1
    fi

    local CurrentAS=$1
    local SshCtnName="${CurrentAS}_ssh"
    docker kill "${SshCtnName}" 2>/dev/null || true

    # enough to just restart the container
    docker restart "${SshCtnName}" 1>/dev/null
}

# restart the web and the web proxy container
restart_web_proxy() {
    local WebCtnName="WEB"
    local WebProxyCtnName="PROXY"

    docker kill "${WebCtnName}" 2>/dev/null || true
    docker kill "${WebProxyCtnName}" 2>/dev/null || true

    docker restart "${WebCtnName}" 1>/dev/null
    docker restart "${WebProxyCtnName}" 1>/dev/null

    echo "Restarted WEB and PROXY"

}

# restart the measurement
restart_mesaurement() {
    local MeasureCtnName="MEASUREMENT"

    docker kill "${MeasureCtnName}" 2>/dev/null || true

    # clean up the old netns of the container
    clean_ctn_netns "${MeasureCtnName}"
    clean_ip_link

    docker restart "${MeasureCtnName}" 1>/dev/null
    echo "Restarted MEASUREMENT"

    # re-link the MEASUREMENT to the routers
    for ((k = 0; k < GroupNumber; k++)); do
        GroupK=(${ASConfig[$k]})         # group config file array
        GroupAS="${GroupK[0]}"           # AS number
        GroupType="${GroupK[1]}"         # IXP/AS
        GroupRouterConfig="${GroupK[3]}" # L3 router config file

        if [ "${GroupType}" != "IXP" ]; then
            readarray Routers <"${DIRECTORY}"/config/$GroupRouterConfig
            RouterNumber=${#Routers[@]}
            for ((i = 0; i < RouterNumber; i++)); do
                RouterI=(${Routers[$i]})      # router config file array
                RouterRegion="${RouterI[0]}"  # region name
                RouterService="${RouterI[1]}" # measurement/matrix/dns
                if [[ "$RouterService" == "MEASUREMENT" ]]; then
                    connect_one_measurement "${GroupAS}" "${RouterRegion}"
                    echo "Reconnected MEASUREMENT to ${RouterRegion} in ${GroupAS}"
                fi
            done
        fi
    done

    if [ "$(check_service_is_required "DNS")" == "True" ]; then
        connect_service_interfaces \
            "MEASUREMENT" "dns" "$(subnet_router_DNS -1 "measurement")" \
            "DNS" "measurement" "$(subnet_router_DNS -1 "dns-measurement")" \
            -1  # -1 to set up IPs in both containers but no default routes.
        echo "Reconnected DNS to MEASUREMENT"
    fi

}

# restart the DNS
restart_dns() {
    local DnsCtnName="DNS"

    docker kill "${DnsCtnName}" 2>/dev/null || true

    # clean up the old netns of the container
    clean_ctn_netns "${DnsCtnName}"
    clean_ip_link

    docker restart "${DnsCtnName}" 1>/dev/null
    echo "Restarted DNS"

    # re-link the DNS to the routers
    for ((k = 0; k < GroupNumber; k++)); do
        GroupK=(${ASConfig[$k]})         # group config file array
        GroupAS="${GroupK[0]}"           # AS number
        GroupType="${GroupK[1]}"         # IXP/AS
        GroupRouterConfig="${GroupK[3]}" # L3 router config file

        if [ "${GroupType}" != "IXP" ]; then
            readarray Routers <"${DIRECTORY}"/config/$GroupRouterConfig
            RouterNumber=${#Routers[@]}
            for ((i = 0; i < RouterNumber; i++)); do
                RouterI=(${Routers[$i]})      # router config file array
                RouterRegion="${RouterI[0]}"  # region name
                RouterService="${RouterI[1]}" # measurement/matrix/dns
                if [[ "$RouterService" == "DNS" ]]; then
                    connect_one_dns "${GroupAS}" "${RouterRegion}"
                    echo "Reconnected DNS to ${RouterRegion} in ${GroupAS}"
                fi
            done
        fi
    done

    if [ "$(check_service_is_required "MEASUREMENT")" == "True" ]; then
        connect_service_interfaces \
            "DNS" "measurement" "$(subnet_router_DNS -1 "dns-measurement")" \
            "MEASUREMENT" "dns" "$(subnet_router_DNS -1 "measurement")" \
            -1  # -1 to set up IPs in both containers but no default routes.
        echo "Reconnected DNS to MEASUREMENT"
    fi
}

# restart the matrix
restart_matrix() {

    local MatrixCtnName="MATRIX"

    docker kill "${MatrixCtnName}" 2>/dev/null || true

    # clean up the old netns of the container
    clean_ctn_netns "${MatrixCtnName}"
    clean_ip_link

    docker restart "${MatrixCtnName}" 1>/dev/null
    echo "Restarted MATRIX"

    # local MatrixConfigDir="${DIRECTORY}"/groups/matrix/

    # # Delete the MATRIX container if it is there.
    # docker rm -f "MATRIX"

    # # Recreate it.
    # docker run -itd --net='none' --name="MATRIX" --hostname="MATRIX" \
    #     --privileged \
    #     --sysctl net.ipv4.icmp_ratelimit=0 \
    #     --sysctl net.ipv4.ip_forward=0 \
    #     -v /etc/timezone:/etc/timezone:ro \
    #     -v /etc/localtime:/etc/localtime:ro \
    #     -v "${MatrixConfigDir}"/destination_ips.txt:/home/destination_ips.txt \
    #     -v "${MatrixConfigDir}"/connectivity.txt:/home/connectivity.txt \
    #     -v "${MatrixConfigDir}"/stats.txt:/home/stats.txt \
    #     -e "UPDATE_FREQUENCY=${MATRIX_FREQUENCY}" \
    #     -e "CONCURRENT_PINGS=${MATRIX_CONCURRENT_PINGS}" \
    #     -e "PING_FLAGS=${MATRIX_PING_FLAGS}" \
    #     "${DOCKERHUB_PREFIX}d_matrix" >/dev/null

    docker pause MATRIX # wait until connected

    # Re-link the MATRIX to the routers
    for ((k = 0; k < GroupNumber; k++)); do
        GroupK=(${ASConfig[$k]})         # group config file array
        GroupAS="${GroupK[0]}"           # AS number
        GroupType="${GroupK[1]}"         # IXP/AS
        GroupRouterConfig="${GroupK[3]}" # L3 router config file

        if [ "${GroupType}" != "IXP" ]; then
            readarray Routers <"${DIRECTORY}"/config/$GroupRouterConfig
            RouterNumber=${#Routers[@]}
            for ((i = 0; i < RouterNumber; i++)); do
                RouterI=(${Routers[$i]})      # router config file array
                RouterRegion="${RouterI[0]}"  # region name
                RouterService="${RouterI[1]}" # measurement/matrix/dns
                if [[ "$RouterService" == "MATRIX" ]]; then
                    connect_one_matrix "${GroupAS}" "${RouterRegion}"
                    echo "Reconnected MATRIX to ${RouterRegion} in ${GroupAS}"
                fi
            done

        fi
    done

    docker unpause MATRIX
}


# try to parse arguments and throw errors on wrong usage
case $1 in
    router)
        if [ "$#" -ne 3 ]; then
            print_usage
            exit 1
        fi
        CurrentAS=$2
        CurrentRegion=$3
        restart_one_router "${CurrentAS}" "${CurrentRegion}"
        ;;
    l3-host)
        if [ "$#" -ne 4 ]; then
        print_usage
        exit 1
           fi
        CurrentAS=$2
        CurrentRegion=$3
        CurrentHostName=$4
        restart_one_l3_host "${CurrentAS}" "${CurrentRegion}" "${CurrentHostName}"
        ;;
    l2-host)
        if [ "$#" -ne 3 ]; then
        print_usage
        exit 1
           fi
        CurrentAS=$2
        CurrentHostName=$3
        restart_one_l2_host "${CurrentAS}" "${CurrentHostName}"
        ;;
    switch)
        if [ "$#" -ne 3 ]; then
        print_usage
        exit 1
           fi
        CurrentAS=$2
        CurrentSwitchName=$3
        restart_one_l2_switch "${CurrentAS}" "${CurrentSwitchName}"
        ;;
    ixp)
        if [ "$#" -ne 2 ]; then
        print_usage
        exit 1
           fi
        CurrentAS=$2
        restart_one_ixp "${CurrentAS}"
        ;;
    ssh)
        if [ "$#" -ne 2 ]; then
        print_usage
        exit 1
           fi
        CurrentAS=$2
        restart_one_ssh "${CurrentAS}"
        ;;
    matrix)
        if [ "$#" -ne 1 ]; then
        print_usage
        exit 1
           fi
        restart_matrix
        ;;
    dns)
        if [ "$#" -ne 1 ]; then
        print_usage
        exit 1
           fi
        restart_dns
        ;;
    measurement)
        if [ "$#" -ne 1 ]; then
        print_usage
        exit 1
           fi
        restart_mesaurement
        ;;
    web)
        if [ "$#" -ne 1 ]; then
        print_usage
        exit 1
           fi
        restart_web_proxy
        ;;
    *)
        print_usage
        exit 1
        ;;
esac
