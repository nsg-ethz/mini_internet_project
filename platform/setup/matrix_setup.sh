#!/bin/bash
#
# start matrix container
# setup links between groups and matrix container

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"
source "${DIRECTORY}"/config/subnet_config.sh

# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt
readarray routers < "${DIRECTORY}"/config/router_config.txt

location="${DIRECTORY}"/groups/matrix/
mkdir $location
echo '' > "$location"/ping_all_groups.sh
chmod +x "${location}"/ping_all_groups.sh


group_numbers=${#groups[@]}
n_routers=${#routers[@]}

# start matrix container
docker run -itd --net='none' --name="MATRIX" --privileged --pids-limit 500 \
    -v "${location}"/ping_all_groups.sh:/home/ping_all_groups.sh thomahol/d_matrix

echo -n "-- add-br matrix " >> "${DIRECTORY}"/groups/add_bridges.sh
echo "ifconfig matrix 0.0.0.0 up" >> "${DIRECTORY}"/groups/ip_setup.sh

for ((i=0;i<n_routers;i++)); do
  router_i=(${routers[$i]})
  rname="${router_i[0]}"
  property1="${router_i[1]}"

  if [ "${property1}" = "MATRIX"  ];then
    for ((k=0;k<group_numbers;k++)); do
      group_k=(${groups[$k]})
      group_number="${group_k[0]}"
      group_as="${group_k[1]}"

      if [ "${group_as}" != "IXP" ];then
        subnet_bridge="$(subnet_router_MATRIX "${group_number}" "bridge")"
        subnet_matrix="$(subnet_router_MATRIX "${group_number}" "matrix")"
        subnet_group="$(subnet_router_MATRIX "${group_number}" "group")"

        ./setup/ovs-docker.sh add-port matrix group_"${group_number}"  \
        MATRIX --ipaddress="${subnet_matrix}"

        ./setup/ovs-docker.sh add-port matrix matrix_"${group_number}" \
        "${group_number}"_"${rname}"router --ipaddress="${subnet_group}" \
        --macaddress="aa:11:11:11:11:"${group_number}

        ./setup/ovs-docker.sh connect-ports matrix \
        group_"${group_number}" MATRIX \
        matrix_"${group_number}" "${group_number}"_"${rname}"router
      fi
    done
  fi
done
