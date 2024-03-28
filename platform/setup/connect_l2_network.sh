#!/bin/bash
#
# Connects the L2 network
#

# sanity check
trap 'exit 1' ERR # catch more error
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
source "${DIRECTORY}"/config/variables.sh

# Needed to create the VLAN on the router interface
modprobe 8021q

readarray ASConfig < "${DIRECTORY}"/config/AS_config.txt
GroupNumber=${#ASConfig[@]}

# TODO: Specify link properties to a gateway router in a config file instead.
for ((k = 0; k < GroupNumber; k++)); do
    GroupK=(${ASConfig[$k]})           # group config file array
    GroupAS="${GroupK[0]}"             # ASN
    GroupType="${GroupK[1]}"           # IXP/AS
    GroupRouterConfig="${GroupK[3]}"   # router config file
    GroupL2SwitchConfig="${GroupK[5]}" # l2 switch config file
    GroupL2HostConfig="${GroupK[6]}"   # l2 host config file
    GroupL2LinkConfig="${GroupK[7]}"   # l2 link config file

    if [ "${GroupType}" != "IXP" ]; then

        readarray Routers < "${DIRECTORY}/config/$GroupRouterConfig"
        readarray L2Switches < "${DIRECTORY}/config/$GroupL2SwitchConfig"
        readarray L2Links < "${DIRECTORY}/config/$GroupL2LinkConfig"
        readarray L2Hosts < "${DIRECTORY}/config/$GroupL2HostConfig"

        L2SwitchNumber=${#L2Switches[@]}
        L2LinkNumber=${#L2Links[@]}
        L2HostNumber=${#L2Hosts[@]}

        # add bridges to the L2 switches
        for ((i = 0; i < L2SwitchNumber; i++)); do
            L2SwitchI=(${L2Switches[$i]}) # L2 switch row
            DCName="${L2SwitchI[0]}"      # DC name
            SWName="${L2SwitchI[1]}"      # switch name
            MacAddress="${L2SwitchI[3]}"  # mac address
            StpPriority="${L2SwitchI[4]}" # stp priority

            SwCtnName="${GroupAS}_L2_${DCName}_${SWName}"

            docker exec -d "${SwCtnName}" ovs-vsctl \
                -- add-br br0 \
                -- set bridge br0 stp_enable=true \
                -- set-fail-mode br0 standalone \
                -- set bridge br0 other_config:stp-system-id=${MacAddress} \
                -- set bridge br0 other_config:stp-priority=${StpPriority}

        done

        # connect L2 switches
        for ((i = 0; i < L2LinkNumber; i++)); do
            # cannot run in parallel as the same switch can be accessed by multiple links
            L2LinkI=(${L2Links[$i]})   # L2 link row
            DC1="${L2LinkI[0]}"        # DC1
            SW1="${L2LinkI[1]}"        # SW1
            DC2="${L2LinkI[2]}"        # DC2
            SW2="${L2LinkI[3]}"        # SW2
            Throughput="${L2LinkI[4]}" # throughput
            Delay="${L2LinkI[5]}"      # delay
            Buffer="${L2LinkI[6]}"     # buffer latency (in ms)

            connect_one_l2_switch "${GroupAS}" "${DC1}" "${SW1}" "${DC2}" "${SW2}" "${Throughput}" "${Delay}" "${Buffer}"

        done

        # connect L2 hosts and configure L2 VPN
        for ((i = 0; i < L2HostNumber; i++)); do
            L2HostI=(${L2Hosts[$i]})   # L2 host row
            HostName="${L2HostI[0]}"   # host name
            DCName="${L2HostI[2]}"     # DC name
            SWName="${L2HostI[3]}"     # switch name
            Throughput="${L2HostI[4]}" # throughput
            Delay="${L2HostI[5]}"      # delay
            Buffer="${L2HostI[6]}"     # buffer latency (in ms)

            connect_one_l2_host "${GroupAS}" "${DCName}" "${SWName}" "${HostName}" "${Throughput}" "${Delay}" "${Buffer}" > /dev/null
        done

        # connect the switch and the gateway router
        for ((i = 0; i < L2SwitchNumber; i++)); do
            # not parallel because the gateway number is small, e.g., 3
            L2SwitchI=(${L2Switches[$i]}) # L2 switch row
            DCName="${L2SwitchI[0]}"      # DC name
            SWName="${L2SwitchI[1]}"      # switch name
            RouterName="${L2SwitchI[2]}"  # gateway router name
            Throughput=$DEFAULT_THROUGHPUT 
            Delay=$DEFAULT_DELAY
            Buffer=$DEFAULT_BUFFER

            # only connect if the router is not N/A
            if [ "${RouterName}" != "N/A" ]; then
                connect_one_l2_gateway "${GroupAS}" "${DCName}" "${SWName}" \
                    "${RouterName}" "${Throughput}" "${Delay}" "${Buffer}" > /dev/null
            fi
        done
        echo "Connected L2 network in group ${GroupAS}"
    fi
done
wait
