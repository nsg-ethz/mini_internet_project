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

  #   for ((i=0;i<n_intern_links;i++)); do
  #     row_i=(${intern_links[$i]})
  #     router1="${row_i[0]}"
  #     router2="${row_i[1]}"
  #     throughput="${row_i[2]}"
  #     delay="${row_i[3]}"
  #
  #     br_name="int-""${group_number}""-""${i}"
  #
  #     echo -n "-- --if-exists del-br "${br_name}" " >> "${DIRECTORY}"/ovs_command.txt
  #
  #   done

    fi
done
