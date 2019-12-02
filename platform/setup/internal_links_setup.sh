#!/bin/bash
#
# create links between routers inside the AS
# links defined in ./config/internal_links_config.txt
# ip subnets defined in ./config/subnet_config.sh

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

        echo -n "-- add-br "${br_name}" " >> "${DIRECTORY}"/groups/add_bridges.sh
        echo "ifconfig "${br_name}" 0.0.0.0 up" >> "${DIRECTORY}"/groups/ip_setup.sh


        for ((i=0;i<n_intern_links;i++)); do
            row_i=(${intern_links[$i]})
            router1="${row_i[0]}"
            router2="${row_i[1]}"
            throughput="${row_i[2]}"
            delay="${row_i[3]}"

            subnet_router1="$(subnet_router_router_intern ${group_number} ${i} 1)"
            subnet_router2="$(subnet_router_router_intern ${group_number} ${i} 2)"

            ./setup/ovs-docker.sh add-port "${br_name}" "port_""${router2}" \
            "${group_number}"_"${router1}"router --ipaddress="${subnet_router1}" \
            --delay="${delay}" --throughput="${throughput}"

            ./setup/ovs-docker.sh add-port "${br_name}" "port_""${router1}" \
            "${group_number}"_"${router2}"router --ipaddress="${subnet_router2}" \
            --delay="${delay}" --throughput="${throughput}"

            ./setup/ovs-docker.sh connect-ports "${br_name}" \
            "port_""${router2}" "${group_number}"_"${router1}"router \
            "port_""${router1}" "${group_number}"_"${router2}"router
        done
    fi
done
