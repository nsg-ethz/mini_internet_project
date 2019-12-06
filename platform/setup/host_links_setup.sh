#!/bin/bash
#
# create links between hosts and routers
# if router has a host, defined in ./config/router_config.txt
# ip subnets are defined in ./config/subnet_config.sh

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"
source "${DIRECTORY}"/config/subnet_config.sh

readarray groups < "${DIRECTORY}"/config/AS_config.txt
readarray routers < "${DIRECTORY}"/config/router_config.txt
group_numbers=${#groups[@]}
n_routers=${#routers[@]}

for ((k=0;k<group_numbers;k++)); do
    group_k=(${groups[$k]})
    group_number="${group_k[0]}"
    group_as="${group_k[1]}"
    if [ "${group_as}" != "IXP" ];then

        br_name="${group_number}"-host

        echo -n "-- add-br "${br_name}" " >> "${DIRECTORY}"/groups/add_bridges.sh
        echo "ifconfig "${br_name}" 0.0.0.0 up" >> "${DIRECTORY}"/groups/ip_setup.sh

        for ((i=0;i<n_routers;i++)); do
            router_i=(${routers[$i]})
            rname="${router_i[0]}"
            property1="${router_i[1]}"
            property2="${router_i[2]}"

            if [ "${property2}" == "host" ];then

                subnet_bridge="$(subnet_host_router "${group_number}" "${i}" "bridge")"
                subnet_router="$(subnet_host_router "${group_number}" "${i}" "router")"
                subnet_host="$(subnet_host_router "${group_number}" "${i}" "host")"

                ./setup/ovs-docker.sh add-port ${br_name} "host"  \
                "${group_number}"_"${rname}"router

                ./setup/ovs-docker.sh add-port ${br_name} "${rname}""router" \
                "${group_number}"_"${rname}"host

                ./setup/ovs-docker.sh connect-ports "${br_name}" \
                "host" "${group_number}"_"${rname}"router \
                "${rname}""router" "${group_number}"_"${rname}"host

                # set default gw in host
                echo "docker exec -i "${group_number}"_"${rname}"host ip route add default via "${subnet_router%/*}" &" >> "${DIRECTORY}"/groups/ip_setup.sh
            fi
        done
    fi
done
