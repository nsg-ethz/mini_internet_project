#!/bin/bash
#
# delete links between routers inside the AS
# links defined in ./config/internal_links_config.txt

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"
source "${DIRECTORY}"/config/subnet_config.sh


# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt
readarray intern_links < "${DIRECTORY}"/config/internal_links_config.txt

group_numbers=${#groups[@]}
n_intern_links=${#intern_links[@]}

for ((k=0;k<group_numbers;k++)); do
    group_k=(${groups[$k]})
    group_number="${group_k[0]}"
    group_as="${group_k[1]}"


    if [ "${group_as}" != "IXP" ];then

        br_name="int-""${group_number}"
        echo -n "-- --if-exists del-br "${br_name}" " >> "${DIRECTORY}"/ovs_command.txt
    fi
done
