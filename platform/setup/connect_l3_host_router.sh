#!/bin/bash
#
# Connects the L3 host and router containers in each group.
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
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <directory>"
    exit 1
fi

DIRECTORY=$1
source "${DIRECTORY}"/config/subnet_config.sh
source "${DIRECTORY}"/setup/_parallel_helper.sh
source "${DIRECTORY}"/groups/docker_pid.map
source "${DIRECTORY}"/setup/_connect_utils.sh
readarray ASConfig < "${DIRECTORY}"/config/AS_config.txt
GroupNumber=${#ASConfig[@]}

for ((k = 0; k < GroupNumber; k++)); do
    GroupK=(${ASConfig[$k]})         # group config file array
    GroupAS="${GroupK[0]}"           # ASN
    GroupType="${GroupK[1]}"         # IXP/AS
    GroupHasConfig="${GroupK[2]}"    # Config/NoConfig
    GroupRouterConfig="${GroupK[3]}" # L3 router config file

    if [ "${GroupType}" != "IXP" ]; then

        readarray Routers < "${DIRECTORY}"/config/$GroupRouterConfig
        RouterNumber=${#Routers[@]}

        # check whether there exists the same router in the first column of Routers,
        # then cannot run in parallel
        AccessSameRouter=false
        for ((i = 0; i < RouterNumber; i++)); do
            RouterI=(${Routers[$i]})
            RouterRegion="${RouterI[0]}"
            for ((j = i + 1; j < RouterNumber; j++)); do
                RouterJ=(${Routers[$j]})
                RouterRegionJ="${RouterJ[0]}"
                if [[ "${RouterRegion}" == "${RouterRegionJ}" ]]; then
                    AccessSameRouter=true
                    break
                fi
            done
            if [[ "${AccessSameRouter}" == true ]]; then
                break
            fi
        done

        # if access the same router, cannot run in parallel
        if [[ "${AccessSameRouter}" == true ]]; then
            for ((i = 0; i < RouterNumber; i++)); do
                # cannot run in parallel because some ASes connect multiple hosts to the same router
                RouterI=(${Routers[$i]})     # router row
                RouterRegion="${RouterI[0]}" # region name
                HostImage="${RouterI[2]}"    # docker image

                HostSuffix=""
                if [[ ${#RouterI[@]} -gt 4 && "${RouterI[4]}" == "ALL" ]]; then
                    HostSuffix="${i}"
                fi

                if [[ "${HostImage}" != "N/A" ]]; then

                    # connect_one_l3_host_router "${GroupAS}" "${RouterRegion}"
                    read -r HostPID RouterPID HostInterface RouterInterface \
                        < <(connect_one_l3_host_router "${GroupAS}" "${RouterRegion}" "${HostSuffix}")

                    # set default ip address and default gw in host
                    if [ "$GroupHasConfig" == "Config" ]; then
                        # this configuration can only be done after the interface is set up!

                        RouterSubnet="$(subnet_host_router "${GroupAS}" "${i}" "router")"
                        HostSubnet="$(subnet_host_router "${GroupAS}" "${i}" "host")"

                        # add the interface address and the default gateway on the host
                        ip netns exec $HostPID ip addr add $HostSubnet dev $HostInterface
                        ip netns exec $HostPID ip route add default via ${RouterSubnet%/*}

                    fi
                fi
            done

        else
            # run in parallel
            for ((i = 0; i < RouterNumber; i++)); do
                (
                    RouterI=(${Routers[$i]})                               # router row
                    RouterRegion="${RouterI[0]}"                           # region name
                    HostImage=$(echo "${RouterI[2]}" | cut -s -d ':' -f 2) # docker image

                    HostSuffix=""
                    if [[ ${#RouterI[@]} -gt 4 && "${RouterI[4]}" == "ALL" ]]; then
                        HostSuffix="${i}"
                    fi

                    if [[ -n "${HostImage}" ]]; then

                        # connect_one_l3_host_router "${GroupAS}" "${RouterRegion}"
                        read -r HostPID RouterPID HostInterface RouterInterface \
                            < <(connect_one_l3_host_router "${GroupAS}" "${RouterRegion}" "${HostSuffix}")

                        # set default ip address and default gw in host
                        if [ "$GroupHasConfig" == "Config" ]; then
                            # this configuration can only be done after the interface is set up!

                            RouterSubnet="$(subnet_host_router "${GroupAS}" "${i}" "router")"
                            HostSubnet="$(subnet_host_router "${GroupAS}" "${i}" "host")"

                            # add the interface address and the default gateway on the host
                            ip netns exec $HostPID ip addr add $HostSubnet dev $HostInterface
                            ip netns exec $HostPID ip route add default via ${RouterSubnet%/*}

                        fi
                    fi
                ) & # only one link in each process
                wait_if_n_tasks_are_running
            done
        fi
        echo "Connected L3 hosts in group ${GroupAS}"
    fi
done
wait
