#!/bin/bash
#
# If RPKI is configured _after_ an invalid route has been accepeted, this
# route is not removed from the routing table. This script checks if there
# are any invalid routes in the routing table and if so, it prints the
# command to clear the BGP session that will remove the invalid routes.
#
# Remove the "echo" on line 61 if you want to clear the BGP session directly.


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

            needs_clear=false
            if [ $n_routinator_addrs -ne 0 ]; then
                for ((i=0;i<n_routers;i++)); do
                    router_i=(${routers[$i]})
                    rname="${router_i[0]}"

                    container="${group_number}_${rname}router"

                    # Match invalid routes, but ignore static routes
                    # (i.e. self-setup hijacks)
                    if docker exec ${container} vtysh -c 'show ip bgp' | grep '^I' | grep -v 0.0.0.0 > /dev/null ; then
                        needs_clear=true
                    fi
                done
            fi
            if [ "$needs_clear" = true ]; then
                echo "sudo ./setup/bgp_clear.sh . ${group_number}"
                sudo ./setup/bgp_clear.sh . ${group_number}
            fi
        fi
    ) &

    wait_if_n_tasks_are_running
done

wait
