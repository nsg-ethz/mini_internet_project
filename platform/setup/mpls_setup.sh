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
source "${DIRECTORY}"/setup/_parallel_helper.sh


# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt
group_numbers=${#groups[@]}

for ((k=0;k<group_numbers;k++)); do
    (
        group_k=(${groups[$k]})
        group_number="${group_k[0]}"
        group_as="${group_k[1]}"
        group_config="${group_k[2]}"
        group_router_config="${group_k[3]}"
        group_internal_links="${group_k[4]}"

        if [ "${group_as}" != "IXP" ];then

            readarray intern_links < "${DIRECTORY}"/config/$group_internal_links
            n_intern_links=${#intern_links[@]}

            for ((i=0;i<n_intern_links;i++)); do
                row_i=(${intern_links[$i]})
                router1="${row_i[0]}"
                router2="${row_i[1]}"
                IFS=',' read -r -a throughput_array <<< "${row_i[2]}"
                IFS=',' read -r -a delay_array <<< "${row_i[3]}"
                throughput_array_index=$((group_number%${#throughput_array[@]}))
                throughput="${throughput_array[$throughput_array_index]}"

                docker exec -d ${group_number}_${router1}router sysctl -w net.mpls.conf."port_${router2}".input=1
                docker exec -d ${group_number}_${router2}router sysctl -w net.mpls.conf."port_${router1}".input=1
            done
        fi
    ) &

    wait_if_n_tasks_are_running
done

wait
