#!/bin/bash
#
# delete bridge to ssh container
# delete bridges between group and group container

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"
source "${DIRECTORY}"/config/subnet_config.sh

# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt
# readarray intern_links < "${DIRECTORY}"/config/internal_links_config.txt
# readarray extern_links < "${DIRECTORY}"/config/external_links_config.txt

group_numbers=${#groups[@]}
# n_intern_links=${#intern_links[@]}
# n_extern_links=${#extern_links[@]}

# bridge for connection from host to ssh containers
echo -n "-- --if-exists del-br ssh_to_group " >> "${DIRECTORY}"/ovs_command.txt

for ((k=0;k<group_numbers;k++)); do
  group_k=(${groups[$k]})
  group_number="${group_k[0]}"
  group_as="${group_k[1]}"

  if [ "${group_as}" != "IXP" ];then

    echo -n "-- --if-exists del-br "${group_number}"-ssh " >> "${DIRECTORY}"/ovs_command.txt
  fi
done

for pid in $(sudo ps aux | grep '157.0.0.11' | awk "{print \$2}" | xargs)
do
    sudo kill -9 $pid &> /dev/null || true
done
