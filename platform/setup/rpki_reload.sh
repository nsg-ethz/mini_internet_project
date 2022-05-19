#!/bin/bash
#
# Update the rpki cache for all Routinator instances and clear all BGP sessions to force rpki rules to be applied.
#
# NOTE: This must be executed after BGP routes have converged!

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"

source "${DIRECTORY}"/config/subnet_config.sh
source "${DIRECTORY}"/setup/_parallel_helper.sh

# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt
readarray routinator_containers < "${DIRECTORY}"/groups/rpki/routinator_containers.txt

group_numbers=${#groups[@]}
n_routinator_containers=${#routinator_containers[@]}

for ((j=0;j<n_routinator_containers;j++)); do
    (
        container_data=(${routinator_containers[$j]})
        n_container_data=${#container_data[@]}

        # Filter out empty lines
        if [ $n_container_data -ge 2 ]; then
            group_number="${container_data[0]}"
            container_name="${container_data[1]}"

            # Enforce a cache update for Routinator.
            docker exec $container_name bash -c "routinator update"
        fi
    ) &

    wait_if_n_tasks_are_running
done

wait

for ((k=0;k<group_numbers;k++)); do
    (
        group_k=(${groups[$k]})
        group_number="${group_k[0]}"
        group_as="${group_k[1]}"
        group_config="${group_k[2]}"
        group_router_config="${group_k[3]}"
        group_internal_links="${group_k[4]}"

        if [ "${group_as}" != "IXP" ]; then
            readarray routers < "${DIRECTORY}"/config/$group_router_config
            readarray intern_links < "${DIRECTORY}"/config/$group_internal_links
            readarray routinator_addrs < "${DIRECTORY}/groups/g${group_number}/routinator.txt"

            n_routers=${#routers[@]}
            n_intern_links=${#intern_links[@]}
            n_routinator_addrs=${#routinator_addrs[@]}

            if [ $n_routinator_addrs -ne 0 ]; then
                for ((i=0;i<n_routers;i++)); do
                    router_i=(${routers[$i]})
                    rname="${router_i[0]}"

                    docker exec ${group_number}"_"${rname}"router" vtysh \
                        -c 'conf t' \
                            -c 'rpki' \
                                -c 'rpki reset' \
                                -c 'exit' \
                            -c 'exit' \
                        -c 'clear ip bgp *' \
                        -c 'exit'
                done
            fi
        fi
    ) &

    wait_if_n_tasks_are_running
done

wait
