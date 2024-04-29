#!/bin/bash
#
# The routes in DNS, Measurement, and Matrix are incorrect. This script fixes
# them. When you start the network from scratch, it should not be necessary.


set -o errexit
set -o pipefail
set -o nounset

DIRECTORY=$(readlink -f $1)

source "${DIRECTORY}"/config/subnet_config.sh
source "${DIRECTORY}"/setup/_parallel_helper.sh

# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt


group_numbers=${#groups[@]}

dexec() {
    docker exec $@
}

for ((k=0;k<group_numbers;k++)); do
    group_k=(${groups[$k]})
    group_number="${group_k[0]}"
    group_as="${group_k[1]}"
    (
        if [ "${group_as}" != "IXP" ]; then
            # DNS: remove default route, add group route
            dexec DNS ip route del "default via 198.${group_number}.0.1 dev group_${group_number}  metric ${group_number}"
            dexec DNS ip route add "${group_number}.0.0.0/8 via 198.${group_number}.0.1 dev group_${group_number}"

            # Matrix: just add group routes, keep defaults
            dexec MATRIX ip route add "${group_number}.0.0.0/8 via ${group_number}.0.198.1 dev group_${group_number}"

            # Measurement:  just add group routes, keep defaults
            # Note that the interface has a slightly different name.
            dexec MEASUREMENT ip route add "${group_number}.0.0.0/8 via ${group_number}.0.199.1 dev group${group_number}"
        fi
    ) &
    wait_if_n_tasks_are_running
done

wait
