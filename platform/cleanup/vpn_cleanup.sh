#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"

readarray groups < "${DIRECTORY}"/config/AS_config.txt
readarray l2_hosts < "${DIRECTORY}"/config/layer2_hosts_config.txt

group_numbers=${#groups[@]}
n_l2_hosts=${#l2_hosts[@]}

for ((k=0;k<group_numbers;k++)); do
    group_k=(${groups[$k]})
    group_number="${group_k[0]}"
    group_as="${group_k[1]}"
    if [ "${group_as}" != "IXP" ];then
        for ((l=0;l<n_l2_hosts;l++)); do
            host_l=(${l2_hosts[$l]})
            hname="${host_l[0]}"
            vlan="${host_l[4]}"

            if [[ $hname == vpn* ]]; then
                echo -n "-- --if-exists del-br vpnbr_${group_k}_${host_l} " >> "${DIRECTORY}"/ovs_command.txt
            fi
        done
    fi
done


if [ -f "${DIRECTORY}/groups/del_vpns.sh" ]; then
    bash < "${DIRECTORY}"/groups/del_vpns.sh || true
fi
