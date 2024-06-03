#!/bin/bash
#
# Restart the container and reconnect the link
# TODO: may not work when multiple connected containers are stopped simultaneously
# in which case should first restart the other container as well
#

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

# print the usage if not enough arguments are provided
if [[ "$#" -ne 6 ]] && [[ "$#" -ne 2 ]]; then
    echo "Usage: $0 <directory> <AS> <Region> <Device> <DeviceType> <HasConfig>"
    echo "       $0 <directory> <service>"
    exit 1
fi

DIRECTORY=$(readlink -f $1)
source "${DIRECTORY}"/config/variables.sh
source "${DIRECTORY}"/config/subnet_config.sh
source "${DIRECTORY}"/setup/_parallel_helper.sh
source "${DIRECTORY}"/groups/docker_pid.map
source "${DIRECTORY}"/setup/_connect_utils.sh
readarray ASConfig <"${DIRECTORY}"/config/AS_config.txt
GroupNumber=${#ASConfig[@]}

# return the map from a DC name to a DC id
# it is based on the order of the DC name in the L3 router config file
_get_dc_name_to_id() {

    local CurrentAS=$1
    declare -A DCNameToId
    local NextDCId=0

    for ((k = 0; k < GroupNumber; k++)); do
        GroupK=(${ASConfig[$k]})         # group config file array
        GroupAS="${GroupK[0]}"           # ASN
        GroupRouterConfig="${GroupK[3]}" # L3 router config file

        if [[ "${GroupAS}" == "${CurrentAS}" ]]; then
            readarray Routers <"${DIRECTORY}/config/$GroupRouterConfig"
            RouterNumber=${#Routers[@]}
            for ((i = 0; i < RouterNumber; i++)); do
                RouterI=(${Routers[$i]})
                HostType="${RouterI[2]%%:*}"
                # if the host type starts with L2-, get the DC name after L2-
                if [[ "${HostType}" == L2-* ]]; then
                    DCName="${HostType#L2-}"
                    if [[ -z "${DCNameToId[$DCName]+_}" ]]; then
                        DCNameToId[$DCName]=${NextDCId}
                        NextDCId=$((${NextDCId} + 1))
                    fi
                fi
            done
            break
        fi
    done

    for key in "${!DCNameToId[@]}"; do
        echo "$key ${DCNameToId[$key]}"
    done
}

# return the unique VLAN tags used in the L2
_get_unique_vlan_set() {

    local CurrentAS=$1
    local VlanSet=()

    # get the router config file name from ASConfig,
    for ((k = 0; k < GroupNumber; k++)); do
        GroupK=(${ASConfig[$k]})         # group config file array
        GroupAS="${GroupK[0]}"           # ASN
        GroupL2HostConfig="${GroupK[6]}" # l2 host config file

        if [[ "${GroupAS}" == "${CurrentAS}" ]]; then
            readarray L2Hosts <"${DIRECTORY}/config/$GroupL2HostConfig"
            L2HostNumber=${#L2Hosts[@]}
            for ((i = 0; i < L2HostNumber; i++)); do
                L2HostI=(${L2Hosts[$i]})
                VlanTag="${L2HostI[7]}"
                # add to the set if not exists
                for ((j = 0; j < ${#VlanSet[@]}; j++)); do
                    if [[ "${VlanSet[$j]}" == "${VlanTag}" ]]; then
                        break
                    fi
                done
                if [[ $j -eq ${#VlanSet[@]} ]]; then
                    VlanSet+=("${VlanTag}")
                fi
            done
            break
        fi
    done
    echo "${VlanSet[@]}"
}

# return the number of gateway routers for each DC
_get_dc_name_to_gateway_number() {

    local CurrentAS=$1
    declare -A DCNameToGatewayNumber

    for ((k = 0; k < GroupNumber; k++)); do
        GroupK=(${ASConfig[$k]})         # group config file array
        GroupAS="${GroupK[0]}"           # ASN
        GroupRouterConfig="${GroupK[3]}" # L3 router config file

        if [[ "${GroupAS}" == "${CurrentAS}" ]]; then

            readarray Routers <"${DIRECTORY}/config/$GroupRouterConfig"
            RouterNumber=${#Routers[@]}
            for ((i = 0; i < RouterNumber; i++)); do
                RouterI=(${Routers[$i]})
                HostType="${RouterI[2]%%:*}"
                # if the host type starts with L2-, get the DC name after L2-
                if [[ "${HostType}" == L2-* ]]; then
                    DCName="${HostType#L2-}"
                    if [[ -z "${DCNameToGatewayNumber[$DCName]+_}" ]]; then
                        DCNameToGatewayNumber[$DCName]=1
                    else
                        DCNameToGatewayNumber[$DCName]=$((${DCNameToGatewayNumber[$DCName]} + 1))
                    fi
                fi
            done
            break
        fi
    done

    for key in "${!DCNameToGatewayNumber[@]}"; do
        echo "$key ${DCNameToGatewayNumber[$key]}"
    done

}

# return the vlan id of a L2 host, i.e., the last argument in the subnet_l2
_get_l2_host_to_vlan_id() {

    local CurrentAS=$1

    declare -A DCNameToGatewayNumber
    while read -r DCName GatewayNumber; do
        DCNameToGatewayNumber[$DCName]=$GatewayNumber
    done < <(_get_dc_name_to_gateway_number "${CurrentAS}")

    # get all unique VLAN tags used in the L2
    local VlanSet
    IFS=' ' read -r -a VlanSet <<<"$(_get_unique_vlan_set "${CurrentAS}")"

    declare -A DCVlanToHostId
    # for each dc stored in DCNameToGatewayNumber
    # and for each vlan stored in VlanSet
    # initialize the host id
    for DCName in "${!DCNameToGatewayNumber[@]}"; do
        for ((j = 0; j < ${#VlanSet[@]}; j++)); do
            VlanTag="${VlanSet[$j]}"
            DCVlanToHostId[$DCName - $VlanTag]=$((${DCNameToGatewayNumber[$DCName]} + 1))
        done
    done

    # the return dictionary
    declare -A HostToVlanId

    for ((k = 0; k < GroupNumber; k++)); do
        GroupK=(${ASConfig[$k]})         # group config file array
        GroupAS="${GroupK[0]}"           # ASN
        GroupL2HostConfig="${GroupK[6]}" # l2 host config file

        if [[ "${GroupAS}" == "${CurrentAS}" ]]; then
            readarray L2Hosts <"${DIRECTORY}/config/$GroupL2HostConfig"
            L2HostNumber=${#L2Hosts[@]}
            for ((i = 0; i < L2HostNumber; i++)); do
                L2HostI=(${L2Hosts[$i]})
                HostName="${L2HostI[0]}"
                DCName="${L2HostI[2]}"
                VlanTag="${L2HostI[7]}"

                HostToVlanId[$HostName]=${DCVlanToHostId[$DCName - $VlanTag]}
                DCVlanToHostId[$DCName - $VlanTag]=$((${DCVlanToHostId[$DCName - $VlanTag]} + 1))
            done
            break
        fi
    done

    for key in "${!HostToVlanId[@]}"; do
        echo "$key ${HostToVlanId[$key]}"
    done
}

# whether the current group is an all-in-one group
_is_all_in_one() {

    local CurrentAS=$1

    for ((k = 0; k < GroupNumber; k++)); do
        GroupK=(${ASConfig[$k]})         # group config file array
        GroupAS="${GroupK[0]}"           # ASN
        GroupRouterConfig="${GroupK[3]}" # L3 router config file

        if [[ "${GroupAS}" == "${CurrentAS}" ]]; then
            readarray Routers <"${DIRECTORY}/config/$GroupRouterConfig"
            RouterNumber=${#Routers[@]}
            for ((i = 0; i < RouterNumber; i++)); do
                RouterI=(${Routers[$i]})
                if [[ ${#RouterI[@]} -gt 4 && "${RouterI[4]}" == "ALL" ]]; then
                    echo "True"
                else
                    echo "False"
                fi
                break
            done
            break
        fi
    done

}

# return the region Id of a region
_get_region_id() {

    local CurrentAS=$1
    local CurrentRegion=$2

    # get the router config file name from ASConfig,
    for ((k = 0; k < GroupNumber; k++)); do
        GroupK=(${ASConfig[$k]})         # group config file array
        GroupAS="${GroupK[0]}"           # ASN
        GroupRouterConfig="${GroupK[3]}" # L3 router config file

        if [[ "${GroupAS}" == "${CurrentAS}" ]]; then

            readarray Routers <"${DIRECTORY}/config/$GroupRouterConfig"
            RouterNumber=${#Routers[@]}
            for ((i = 0; i < RouterNumber; i++)); do
                RouterI=(${Routers[$i]})
                RouterRegion="${RouterI[0]}"
                if [[ "${RouterRegion}" == "${CurrentRegion}" ]]; then
                    echo "${i}"
                    break
                fi
            done
            break
        fi
    done
}

# whether the host is a krill or a routinator
_is_krill_or_routinator() {
    local CurrentAS=$1
    local CurrentRegion=$2
    local HostName=$3
    local Device=$4 # krill/routinator

    # use suffix to distinguish different hosts in all-in-one router config
    local HostSuffix=$(echo "${HostName}" | sed 's/host//')

    # get the router config file name from ASConfig.
    for ((k = 0; k < GroupNumber; k++)); do
        GroupK=(${ASConfig[$k]})         # group config file array
        GroupAS="${GroupK[0]}"           # ASN
        GroupRouterConfig="${GroupK[3]}" # L3 router config file

        # check if it is an all-in-one AS
        local IsAllInOne=$(_is_all_in_one "${CurrentAS}")

        if [[ "${GroupAS}" == "${CurrentAS}" ]]; then
            readarray Routers <"${DIRECTORY}/config/$GroupRouterConfig"
            RouterNumber=${#Routers[@]}
            for ((i = 0; i < RouterNumber; i++)); do
                RouterI=(${Routers[$i]})
                RouterRegion="${RouterI[0]}"
                HostImage="${RouterI[2]}"
                if [[ "${RouterRegion}" == "${CurrentRegion}" ]]; then
                    # if not all-in-one, not care about the suffix
                    if [[ "${IsAllInOne}" == "False" ]]; then
                        if [[ "${HostImage}" == krill* ]] && [[ "${Device}" == "krill" ]]; then
                            echo "True"
                            break
                        elif [[ "${HostImage}" == routinator* ]] && [[ "${Device}" == "routinator" ]]; then
                            echo "True"
                            break
                        else
                            echo "False"
                            break
                        fi
                    else
                        # also match the suffix
                        if [[ "${HostImage}" == krill* ]] && [[ "${Device}" == "krill" ]] && [[ "${HostSuffix}" == "${i}" ]]; then
                            echo "True"
                            break
                        elif [[ "${HostImage}" == routinator* ]] && [[ "${Device}" == "routinator" ]] && [[ "${HostSuffix}" == "${i}" ]]; then
                            echo "True"
                            break
                        else
                            echo "False"
                            break
                        fi
                    fi
                fi
            done
            break
        fi
    done
}

# restart an L3 host
_restart_one_l3_host() {

    # check enough arguments are provided
    if [ "$#" -ne 4 ]; then
        echo "Usage: _restart_one_l3_host <AS> <Region> <Device> <HasConfig>"
        exit 1
    fi

    local CurrentAS=$1
    local CurrentRegion=$2
    local CurrentHostName=$3
    local HasConfig=$4

    local IsKrill=$(_is_krill_or_routinator "${CurrentAS}" "${CurrentHostName}" "{CurrentRegion}" "krill")
    local IsRoutinator=$(_is_krill_or_routinator "${CurrentAS}" "${CurrentRegion}" "{CurrentHostName}" "routinator")

    local HostSuffix=$(echo "${CurrentHostName}" | sed 's/host//')
    local HostCtnName="${CurrentAS}_${CurrentRegion}host${HostSuffix}"
    local RouterCtnName="${CurrentAS}_${CurrentRegion}router"

    # make sure the container is not running, otherwise will cause error and need to manually clear ip link
    docker kill "${HostCtnName}" || true

    # clean up the old netns of the container
    # this only works if it is the first time to restart the container
    # otherwise the pid will be different
    local OldHostPID=$(get_container_pid "${HostCtnName}" "True")
    if [[ -n "${OldHostPID}" ]]; then
        ip netns del "${OldHostPID}" || true
        rm -f /var/run/netns/"${OldHostPID}" || true
    fi

    echo "Cleaned up the old netns of host ${HostCtnName}"

    docker restart "${HostCtnName}"

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

    local IsAllInOne=$(_is_all_in_one "${CurrentAS}")

    if [[ "${HasConfig}" == "True" ]]; then
        if [[ "${IsAllInOne}" == "False" ]]; then
            local RegionID=$(_get_region_id "${CurrentAS}" "${CurrentRegion}")
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
_restart_one_router() {

    # check enough arguments are provided
    if [ "$#" -ne 3 ]; then
        echo "Usage: _reconnect_one_router <AS> <Region> <HasConfig>"
        exit 1
    fi

    local CurrentAS=$1
    local CurrentRegion=$2
    local HasConfig=$3

    local RouterCtnName="${CurrentAS}_${CurrentRegion}router"

    docker kill "${RouterCtnName}" || true

    # clean up the old netns of the container
    local OldRouterPID=$(get_container_pid "${RouterCtnName}" "True")
    if [[ -n "${OldRouterPID}" ]]; then
        ip netns del "${OldRouterPID}" || true
        rm -f /var/run/netns/"${OldRouterPID}" || true
    fi

    echo "Cleaned up the old netns of router ${RouterCtnName}"

    docker restart "${RouterCtnName}"

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
            if [[ ${#RouterI[@]} -gt 4 && "${RouterI[4]}" == "ALL" ]]; then
                HostSuffix="${i}"
            fi
            local HostCtnName="${CurrentAS}_${CurrentRegion}host${HostSuffix}"

            if [[ "${HostImage}" != "N/A" ]]; then

                read -r HostPID RouterPID HostInterface RouterInterface \
                    < <(connect_one_l3_host_router "${CurrentAS}" "${RouterRegion}" "${HostSuffix}")

                if [[ "${HasConfig}" == "True" ]]; then

                    local IsAllInOne=$(_is_all_in_one "${CurrentAS}")
                    # configure the connected host
                    if [[ "${IsAllInOne}" == "False" ]]; then
                        local RegionID=$(_get_region_id "${CurrentAS}" "${CurrentRegion}")
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

            echo "Reconnected router ${RouterCtnName} to host ${HostCtnName}"
        fi
    done

    # get the unique VLAN set used in the L2
    local VlanSet
    IFS=' ' read -r -a VlanSet <<<"$(_get_unique_vlan_set "${CurrentAS}")"
    # map from the DCName to the DCId
    declare -A DCNameToId
    while read -r DCName DCId; do
        DCNameToId["$DCName"]="$DCId"
    done < <(_get_dc_name_to_id "${CurrentAS}")

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
            RegionId=$(_get_region_id "${CurrentAS}" "${CurrentRegion}")
            for ((j = 0; j < ${#VlanSet[@]}; j++)); do
                VlanTag="${VlanSet[$j]}"
                RouterInterface="${CurrentRegion}-L2.$VlanTag"
                ip netns exec "${RouterPID}" ip link add link "${RouterInterface%.*}" name "${RouterInterface}" type vlan id "${VlanTag}"
            done
            echo "Set up VLAN interfaces on router ${RouterCtnName}"

            # if the current router is one end of the tunnel
            # if the tunnel was set before, the tunnel is gone after restarting the container, but the sit0 interface is kept
            # once a tunnel is set, the sit0 will be displayed on the server and all container!
            # TODO: check the original topo to confirm it is expeted
            if [[ "${HasConfig}" == "True" ]]; then
                if [[ "${RouterName}" == "${TunnelEndA}" ]] || [[ "${RouterName}" == "${TunnelEndB}" ]]; then
                    # configure the 6in4 tunnel
                    EndAId=$(_get_region_id "${CurrentAS}" "${TunnelEndA}")
                    EndBId=$(_get_region_id "${CurrentAS}" "${TunnelEndB}")
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
_restart_one_l2_host() {

    # check enough arguments are provided
    if [ "$#" -ne 4 ]; then
        echo "Usage: _restart_one_l2_host <AS> <DCRegion> <Host> <HasConfig>"
        exit 1
    fi

    local CurrentAS=$1
    local CurrentRegion=$2
    local CurrentHostName=$3
    local HasConfig=$4

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
            done < <(_get_dc_name_to_id "${CurrentAS}")

            declare -A HostToVlanId
            while read -r HostName VlanId; do
                HostToVlanId[$HostName]=$VlanId
            done < <(_get_l2_host_to_vlan_id "${CurrentAS}")

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

                    docker kill "${HostCtnName}" || true

                    # clean up the old netns of the container
                    local OldHostPID=$(get_container_pid "${HostCtnName}" "True")
                    if [[ -n "${OldHostPID}" ]]; then
                        ip netns del "${OldHostPID}" || true
                        rm -f /var/run/netns/"${OldHostPID}" || true
                    fi

                    echo "Cleaned up the old netns of host ${HostCtnName}"

                    docker restart "${HostCtnName}"

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
_restart_one_l2_switch() {
    # check enough arguments are provided
    if [ "$#" -ne 4 ]; then
        echo "Usage: _restart_one_l2_switch <AS> <DCRegion> <Switch> <HasConfig>"
        exit 1
    fi

    local CurrentAS=$1
    local CurrentRegion=$2
    local CurrentSwitch=$3
    local HasConfig=$4

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
            done < <(_get_dc_name_to_id "${CurrentAS}")

            local VlanSet
            IFS=' ' read -r -a VlanSet <<<"$(_get_unique_vlan_set "${CurrentAS}")"

            declare -A HostToVlanId
            while read -r HostName VlanId; do
                HostToVlanId[$HostName]=$VlanId
            done < <(_get_l2_host_to_vlan_id "${CurrentAS}")

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

                    docker kill "${SwitchCtnName}" || true

                    # clean up the old netns of the container
                    local OldSwitchPID=$(get_container_pid "${SwitchCtnName}" "True")
                    if [[ -n "${OldSwitchPID}" ]]; then
                        ip netns del "${OldSwitchPID}" || true
                        rm -f /var/run/netns/"${OldSwitchPID}" || true
                    fi

                    echo "Cleaned up the old netns of switch ${SwitchCtnName}"

                    docker restart "${SwitchCtnName}"

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
                SWNameA="${L2LinkI[0]}"    # switch A name
                SWNameB="${L2LinkI[1]}"    # switch B name
                Throughput="${L2LinkI[2]}" # throughput
                Delay="${L2LinkI[3]}"      # delay
                Buffer="${L2LinkI[4]}"     # buffer latency (in ms)

                if [[ "${SWNameA}" == "${CurrentSwitch}" ]] || [[ "${SWNameB}" == "${CurrentSwitch}" ]]; then
                    connect_one_l2_switches "${GroupAS}" "${DCName}" "${SWNameA}" "${SWNameB}" "${Throughput}" "${Delay}" "${Buffer}"
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
_restart_one_ixp() {
    # check enough arguments are provided
    if [ "$#" -ne 3 ]; then
        echo "Usage: _reconnect_one_ixp <AS> <Region> <HasConfig>"
        exit 1
    fi

    local CurrentAS=$1
    local CurrentRegion=$2
    local HasConfig=$3

    local IXPCtnName="${CurrentAS}_IXP"

    docker kill "${IXPCtnName}" || true
    # TODO: sometimes the interface on the other router container is not cleaned up when the IXP is killed
    # This will lead to `File exixts` error when setting up the veth interface on the router container,
    # In this case, we need to first manually cleaned up dangling interfaces that show in `ip link | grep _b`
    # then kill the IXP container again, wait for some time to confirm the IXP interface on the route container is gonoe
    # then we can continue
    # Sometimes we can also get tc error, in this case just kill and return the restarting function
    # FIRST CHECK THE ROUTER INTERFACE TO MAKE SURE THE INTERFACE IS CLEANED UP!
    sleep 60
    echo "Waited for 60 seconds to clean up the IXP interface on the router container"

    set -x # used to see which router container still has the IXP interface

    # clean up the old netns of the container
    local OldIXPPID=$(get_container_pid "${IXPCtnName}" "True")
    if [[ -n "${OldIXPPID}" ]]; then
        ip netns del "${OldIXPPID}" || true
        rm -f /var/run/netns/"${OldIXPPID}" || true
    fi
    echo "Cleaned up the old netns of IXP ${IXPCtnName}"

    docker restart "${IXPCtnName}"

    echo "Restarted IXP ${IXPCtnName}"

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

_restart_matrix() {
    local MatrixConfigDir="${DIRECTORY}"/groups/matrix/

    # Delete the MATRIX container if it is there.
    docker rm -f "MATRIX"

    # Recreate it.
    docker run -itd --net='none' --name="MATRIX" --hostname="MATRIX" \
        --privileged \
        --sysctl net.ipv4.icmp_ratelimit=0 \
        --sysctl net.ipv4.ip_forward=0 \
        -v /etc/timezone:/etc/timezone:ro \
        -v /etc/localtime:/etc/localtime:ro \
        -v "${MatrixConfigDir}"/destination_ips.txt:/home/destination_ips.txt \
        -v "${MatrixConfigDir}"/connectivity.txt:/home/connectivity.txt \
        -v "${MatrixConfigDir}"/stats.txt:/home/stats.txt \
        -e "UPDATE_FREQUENCY=${MATRIX_FREQUENCY}" \
        -e "CONCURRENT_PINGS=${MATRIX_CONCURRENT_PINGS}" \
        -e "PING_FLAGS=${MATRIX_PING_FLAGS}" \
        "${DOCKERHUB_PREFIX}d_matrix" >/dev/null

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

if [[ "$#" -eq 6 ]]; then
    # $1: platform directory
    RestartAS=$2
    RestartRegion=$3     # ZURI/L2/IXP
    RestartDevice=$4     # host0/host/router/S1/IXP/FIFA_1
    RestartDeviceType=$5 # router/l3-host/switch/l2-host/ixp
    RestartWithConfig=$6 # True or False, used to configure hosts as their network config is reset after restarting

    # restart a L3 host
    if [[ "${RestartDeviceType}" == l3-host ]]; then
        _restart_one_l3_host "${RestartAS}" "${RestartRegion}" "${RestartDevice}" "${RestartWithConfig}"
    fi

    # restart a router
    if [[ "${RestartDeviceType}" == router ]]; then
        _restart_one_router "${RestartAS}" "${RestartRegion}" "${RestartWithConfig}"
    fi

    # restart a L2 host
    if [[ "${RestartDeviceType}" == l2-host ]]; then
        _restart_one_l2_host "${RestartAS}" "${RestartRegion}" "${RestartDevice}" "${RestartWithConfig}"
    fi

    # restart a L2 switch
    if [[ "${RestartDeviceType}" == switch ]]; then
        _restart_one_l2_switch "${RestartAS}" "${RestartRegion}" "${RestartDevice}" "${RestartWithConfig}"
    fi

    # restart an IXP
    if [[ "${RestartDeviceType}" == ixp ]]; then
        # put a random region
        _restart_one_ixp "${RestartAS}" "${RestartRegion}" "${RestartWithConfig}"
    fi
else
    # restart a service
    RestartService=$2

    if [[ "${RestartService,,}" == "matrix" ]]; then
        # Shut down the MATRIX (if it is there)
        _restart_matrix
    fi

fi
