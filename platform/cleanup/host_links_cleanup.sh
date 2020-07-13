#!/bin/bash
#
# delete links between hosts and routers
# if router has a host, defined in ./config/router_config.txt

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"
source "${DIRECTORY}"/config/subnet_config.sh

readarray groups < "${DIRECTORY}"/config/AS_config.txt
group_numbers=${#groups[@]}

for ((k=0;k<group_numbers;k++)); do
    group_k=(${groups[$k]})
    group_number="${group_k[0]}"
    group_as="${group_k[1]}"

    if [ "${group_as}" != "IXP" ];then

        echo -n "-- --if-exists del-br "${group_number}"-host " >> "${DIRECTORY}"/ovs_command.txt
    fi
done
