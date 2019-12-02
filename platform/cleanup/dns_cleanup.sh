#!/bin/bash
#
# delete links between groups and dns server
# delet link between mgt container to dns server

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"
source "${DIRECTORY}"/config/subnet_config.sh

# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt
readarray routers < "${DIRECTORY}"/config/router_config.txt
group_numbers=${#groups[@]}
n_routers=${#routers[@]}

echo -n "-- --if-exists del-br dns " >> "${DIRECTORY}"/ovs_command.txt


# for ((i=0;i<n_routers;i++)); do
#   router_i=(${routers[$i]})
#   rname="${router_i[0]}"
#   property1="${router_i[1]}"
#
#   if [ "${property1}" = "DNS"  ];then
#     for ((k=0;k<group_numbers;k++)); do
#       group_k=(${groups[$k]})
#       group_number="${group_k[0]}"
#       group_as="${group_k[1]}"
#       if [ "${group_as}" != "IXP" ];then
#
# 	br_name="dns_""${group_number}"
# 	echo -n "-- --if-exists del-br "${br_name}" " >> "${DIRECTORY}"/ovs_command.txt
#
#       fi
#     done
#   fi
# done


# del bridge bewteen  mgt to dns service
br_name="dns_mgt"
echo -n "-- --if-exists del-br "${br_name}" " >> "${DIRECTORY}"/ovs_command.txt
