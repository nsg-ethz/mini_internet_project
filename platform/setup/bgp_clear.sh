#!/bin/bash
#
# Clear all BGP sessions.

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"
GROUP="${2:-}"

source "${DIRECTORY}"/config/subnet_config.sh
source "${DIRECTORY}"/setup/_parallel_helper.sh

# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt
readarray routinator_containers < "${DIRECTORY}"/groups/rpki/routinator_containers.txt

group_numbers=${#groups[@]}
n_routinator_containers=${#routinator_containers[@]}

for ((k=0;k<group_numbers;k++)); do
    group_k=(${groups[$k]})
    group_number="${group_k[0]}"
    group_as="${group_k[1]}"
    group_router_config="${group_k[3]}"
    if [ -n "$GROUP" ] && [ "$GROUP" != "$group_number" ]; then
        continue
    fi

    (
        if [ "${group_as}" != "IXP" ]; then
            readarray routers < "${DIRECTORY}"/config/$group_router_config
            readarray routinator_addrs < "${DIRECTORY}/groups/g${group_number}/routinator.txt"

            n_routers=${#routers[@]}
            n_routinator_addrs=${#routinator_addrs[@]}

            if [ $n_routinator_addrs -ne 0 ]; then
                for ((i=0;i<n_routers;i++)); do
                    router_i=(${routers[$i]})
                    rname="${router_i[0]}"

                    docker exec "${group_number}_${rname}router" vtysh \
                        -c 'clear ip bgp *'
                done
            fi
        fi
    ) &

    wait_if_n_tasks_are_running
done

wait
