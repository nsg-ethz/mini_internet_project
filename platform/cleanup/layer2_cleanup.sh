#!/bin/bash
#
# delete links between hosts and switches
# what switch a host is connected is defined in config/layer2_hosts_config.txt
# links between switches are defined in config/layer2_links_config.txt

set -o errexit
set -o pipefail
set -o nounset


DIRECTORY="$1"
source "${DIRECTORY}"/config/subnet_config.sh


# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt
group_numbers=${#groups[@]}


for ((k=0;k<group_numbers;k++)); do
    group_k=(${groups[$k]})
    group_number="${group_k[0]}"
    group_as="${group_k[1]}"
    group_router_config="${group_k[3]}"
    group_internal_links="${group_k[4]}"
    group_layer2_switches="${group_k[5]}"
    group_layer2_hosts="${group_k[6]}"
    group_layer2_links="${group_k[7]}"

    if [ "${group_as}" != "IXP" ]; then
        br_name="l2-"${group_number}
        echo -n "-- --if-exists del-br "${br_name}" " >> "${DIRECTORY}"/ovs_command.txt
    fi
done

modprobe --remove 8021q
