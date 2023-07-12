#!/bin/bash
#
# We randomly observed some routinator instances to crash with the container
# unable to restart them, even though it should be doing that.
# This script can be used in a tmux session and manually keeps the crashed
# routinator instances running. If you stop this script, the routinator
# instances will be stopped again as well.

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

    (
        if [ "${group_as}" != "IXP" ]; then
            if ! docker exec "${group_number}_BASEhost" ps | grep "routinator server" > /dev/null ; then
                echo "sudo docker exec -d ${group_number}_BASEhost routinator server"
            fi
        fi
    )

done

wait
