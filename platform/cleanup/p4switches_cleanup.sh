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

        echo -n "-- --if-exists del-br ${group_number}-p4api" >> "${DIRECTORY}"/ovs_command.txt

        ip link del ${group_number}"-p4switch-api"
    fi
done
