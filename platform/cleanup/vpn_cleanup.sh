#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"

readarray groups < "${DIRECTORY}"/config/AS_config.txt
group_numbers=${#groups[@]}

for ((k=0;k<group_numbers;k++)); do
    group_k=(${groups[$k]})
    group_number="${group_k[0]}"
    group_as="${group_k[1]}"
    group_layer2_switches="${group_k[5]}"
    group_layer2_hosts="${group_k[6]}"
    group_layer2_links="${group_k[7]}"

    if [ "${group_as}" != "IXP" ];then

        readarray l2_hosts < "${DIRECTORY}"/config/$group_layer2_hosts
        n_l2_hosts=${#l2_hosts[@]}

        for ((l=0;l<n_l2_hosts;l++)); do
            host_l=(${l2_hosts[$l]})
            hname="${host_l[0]}"
            vlan="${host_l[5]}"

            if [[ $hname == vpn* ]]; then
                echo -n "-- --if-exists del-br vpnbr_${group_k}_${host_l} " >> "${DIRECTORY}"/ovs_command.txt
            fi
        done
    fi
done


if [ -f "${DIRECTORY}/groups/del_vpns.sh" ]; then
    bash < "${DIRECTORY}"/groups/del_vpns.sh || true
fi
