#!/bin/bash
#
# Restart the container and reconnect the link
# TODO: may not work when multiple connected containers are stopped simultaneously
# in which case should first restart the other container as well
#

# sanity check
# set -x
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
if [[ "$#" -ne 5 ]] && [[ "$#" -ne 3 ]]; then
    echo "Usage: $0 <directory> <AS> <Region> <Device> <HasConfig>"
    echo "       $0 <directory> <docker_user> <service>"
    exit 1
fi

# return the map from a DC name to a DC id
_get_dc_name_to_id() {

    local CurrentAS=$1
    declare -A DCNameToId
    local NextDCId=0

    for ((k = 0; k < GroupNumber; k++)); do
        GroupK=(${ASConfig[$k]})           # group config file array
        GroupAS="${GroupK[0]}"             # ASN
        GroupL2SwitchConfig="${GroupK[5]}" # l2 switch config file

        if [[ "${GroupAS}" == "${CurrentAS}" ]]; then
            readarray L2Switches < "${DIRECTORY}/config/$GroupL2SwitchConfig"
            L2SwitchNumber=${#L2Switches[@]}
            for ((i = 0; i < L2SwitchNumber; i++)); do
                L2SwitchI=(${L2Switches[$i]}) # L2 switch row
                DCName="${L2SwitchI[0]}"      # DC name
                if [[ -z "${DCNameToId[$DCName]+_}" ]]; then
                    DCNameToId[$DCName]=$NextDCId
                    NextDCId=$(($NextDCId + 1))
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
            readarray L2Hosts < "${DIRECTORY}/config/$GroupL2HostConfig"
            L2HostNumber=${#L2Hosts[@]}
            for ((i = 0; i < L2HostNumber; i++)); do
                L2HostI=(${L2Hosts[$i]})
                VlanTag="${L2HostI[6]}"
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

# whether the current group is an all-in-one group
_is_all_in_one() {

    local CurrentAS=$1

    for ((k = 0; k < GroupNumber; k++)); do
        GroupK=(${ASConfig[$k]})         # group config file array
        GroupAS="${GroupK[0]}"           # ASN
        GroupRouterConfig="${GroupK[3]}" # L3 router config file

        if [[ "${GroupAS}" == "${CurrentAS}" ]]; then
            readarray Routers < "${DIRECTORY}/config/$GroupRouterConfig"
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

            readarray Routers < "${DIRECTORY}/config/$GroupRouterConfig"
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
            readarray Routers < "${DIRECTORY}/config/$GroupRouterConfig"
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
_reconnect_one_router() {

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

            readarray Routers < "${DIRECTORY}/config/$GroupRouterConfig"
            readarray InternalLinks < "${DIRECTORY}/config/$GroupInternalLinkConfig"
            readarray L2Switches < "${DIRECTORY}/config/$GroupL2SwitchConfig"
            readarray L2Hosts < "${DIRECTORY}/config/$GroupL2HostConfig"

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
        # TODO: specify these values in a config file
        Throughput=10mbit
        Delay=10ms # manually set a default value
        Buffer=50ms # manually set a default value

        if [[ "${RouterName}" == "${CurrentRegion}" ]]; then
            connect_one_l2_gateway "${CurrentAS}" "${DCName}" "${SWName}" \
                "${RouterName}" "${Throughput}" "${Delay}" "${Buffer}"
            echo "Reconnected l2 switch ${SWName} to router ${RouterName} in ${CurrentAS}"
        fi

        # record the L2 gateway router and the corresponding DC id
        if [[ -z "${RouterToDCId[$RouterName]+_}" ]]; then
            RouterToDCId[$RouterName]="${DCNameToId[$DCName]}"
        fi
    done

    # configure the tunnel and vlan
    local RouterPID=$(get_container_pid "${RouterCtnName}" "False")
    read TunnelEndA TunnelEndB < "${DIRECTORY}/config/l2_tunnel.txt"
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
            echo "Configured VLAN interfaces on router ${RouterCtnName}"

            # if the current router is one end of the tunnel
            # TODO: if the tunnel was set before, the tunnel is gone after restarting the container, but the sit0 interface is kept
            # once a tunnel is set, the sit0 will be displayed on the server and all container!
            # check the original topo to confirm it is expeted
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
    readarray ExternalLinks < "${DIRECTORY}/config/aslevel_links.txt"
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
    # FIXME: maybe still need to clear and reset manually, as the bgp takes time to converge
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

            # get the number of gateway routers in each DC
            declare -A DCNameToGatewayNumber
            readarray Routers < "${DIRECTORY}/config/$GroupRouterConfig"
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
            # get all unique VLAN tags used in the L2
            local VlanSet
            IFS=' ' read -r -a VlanSet <<<"$(_get_unique_vlan_set "${CurrentAS}")"
            # map from the DCName to the DCId
            declare -A DCNameToId
            while read -r DCName DCId; do
                DCNameToId["$DCName"]="$DCId"
            done < <(_get_dc_name_to_id "${CurrentAS}")

            readarray L2Hosts < "${DIRECTORY}/config/$GroupL2HostConfig"
            L2HostNumber=${#L2Hosts[@]}

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

            for ((i = 0; i < L2HostNumber; i++)); do
                L2HostI=(${L2Hosts[$i]})
                HostName="${L2HostI[0]}"
                DCName="${L2HostI[2]}"
                SWName="${L2HostI[3]}"
                Throughput="${L2HostI[4]}"
                Delay="${L2HostI[5]}"
                Buffer="${L2HostI[6]}"
                VlanTag="${L2HostI[7]}"

                if [[ "${HostName}" == "${CurrentHostName}" ]]; then
                    # TODO: don't hardcode the container name
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
                        # get the subnet of host the
                        local HostSubnet=$(subnet_l2 "${GroupAS}" "${DCNameToId[$DCName]}" "${VlanTag}" "${DCVlanToHostId[$DCName - $VlanTag]}")
                        local HostSubnetV6=$(subnet_l2_ipv6 "${GroupAS}" "${DCNameToId[$DCName]}" "${VlanTag}" "${DCVlanToHostId[$DCName - $VlanTag]}")
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

                # increment the host id
                DCVlanToHostId[$DCName - $VlanTag]=$((${DCVlanToHostId[$DCName - $VlanTag]} + 1))
            done
            break
        fi
    done

}

_restart_matrix() {
    local Directory=$1
    local DOCKERHUB_USER=$2
    local GroupNumber=$3
    local MatrixConfigDir="${DIRECTORY}"/groups/matrix/
    local MatrixFrequency=300 # seconds
    local ConcurrentPings=500
    local PIDLIMIT=1500  # Needs to be quite a bit higher than ConcurrentPings

    # Delete the MATRIX container if it is there.
    docker rm -f "MATRIX"

    # Recreate it.
    docker run -itd --net='none' --name="MATRIX" --hostname="MATRIX" \
        --privileged --pids-limit $PIDLIMIT \
        --sysctl net.ipv4.icmp_ratelimit=0 \
        --sysctl net.ipv4.ip_forward=0 \
        -v /etc/timezone:/etc/timezone:ro \
        -v /etc/localtime:/etc/localtime:ro \
        -v "${MatrixConfigDir}"/destination_ips.txt:/home/destination_ips.txt \
        -v "${MatrixConfigDir}"/connectivity.txt:/home/connectivity.txt \
        -v "${MatrixConfigDir}"/stats.txt:/home/stats.txt \
        -e "UPDATE_FREQUENCY=${MatrixFrequency}" \
        -e "CONCURRENT_PINGS=${ConcurrentPings}" \
        "${DOCKERHUB_USER}/d_matrix" > /dev/null

    docker pause MATRIX  # wait until connected

    # Re-link the MATRIX to the routers
    for ((k = 0; k < GroupNumber; k++)); do
        GroupK=(${ASConfig[$k]})         # group config file array
        GroupAS="${GroupK[0]}"           # AS number
        GroupType="${GroupK[1]}"         # IXP/AS
        GroupRouterConfig="${GroupK[3]}" # L3 router config file

        if [ "${GroupType}" != "IXP" ]; then
            readarray Routers < "${DIRECTORY}"/config/$GroupRouterConfig
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


DIRECTORY=$(readlink -f $1)  # Resolve the full path of the directory

source "${DIRECTORY}"/config/subnet_config.sh
source "${DIRECTORY}"/setup/_parallel_helper.sh
source "${DIRECTORY}"/groups/docker_pid.map
source "${DIRECTORY}"/setup/_connect_utils.sh
readarray ASConfig < "${DIRECTORY}"/config/AS_config.txt
GroupNumber=${#ASConfig[@]}


if [[ "$#" -eq 5 ]]; then
    RestartAS=$2
    RestartRegion=$3     # ZURI/L2
    RestartDevice=$4     # host0/host/router/S1/Matrix/IXP/FIFA_1
    RestartWithConfig=$5 # True or False, used to configure hosts as their network config is reset after restarting

    # restart a L3 host
    if [[ "${RestartDevice}" == host* ]]; then
        # is a krill if the container is 1_ZURIhost0
        _restart_one_l3_host "${RestartAS}" "${RestartRegion}" "${RestartDevice}" "${RestartWithConfig}"
    fi

    # restart a router
    if [[ "${RestartDevice}" == router ]]; then
        _reconnect_one_router "${RestartAS}" "${RestartRegion}" "${RestartWithConfig}"
    fi

    # restart a L2 host
    if [[ "${RestartRegion}" == L2 ]]; then
        _restart_one_l2_host "${RestartAS}" "${RestartRegion}" "${RestartDevice}" "${RestartWithConfig}"
    fi
else
    DOCKERHUB_USER=$2
    RestartService=$3

    if [[ "${RestartService,,}" == "matrix" ]]; then
        # Shut down the MATRIX (if it is there)
        _restart_matrix "${DIRECTORY}" "${DOCKERHUB_USER}" "${GroupNumber}"
    fi

fi