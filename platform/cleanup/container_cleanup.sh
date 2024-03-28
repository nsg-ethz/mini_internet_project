#!/bin/bash
#
# delete all group containers(ssh, routers, hosts, switches), DNS, MEASUREMENT and MATRIX

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"
source "${DIRECTORY}"/config/subnet_config.sh

# read configs
# read lines into an array
readarray groups < "${DIRECTORY}"/config/AS_config.txt

group_numbers=${#groups[@]}


for ((k=0;k<group_numbers;k++)); do
    group_k=(${groups[$k]}) # (${}) to execute the command and take the result
    group_number="${group_k[0]}"
    group_as="${group_k[1]}"
    group_config="${group_k[2]}"
    group_router_config="${group_k[3]}"
    group_layer2_switches="${group_k[5]}"
    group_layer2_hosts="${group_k[6]}"
    group_layer2_links="${group_k[7]}"

    if [ "${group_as}" != "IXP" ];then

        readarray routers < "${DIRECTORY}"/config/$group_router_config
        readarray l2_switches < "${DIRECTORY}"/config/$group_layer2_switches
        readarray l2_hosts < "${DIRECTORY}"/config/$group_layer2_hosts
        n_routers=${#routers[@]} # get the number of routers
        n_l2_switches=${#l2_switches[@]}
        n_l2_hosts=${#l2_hosts[@]}

        # kill ssh container
        # immediately sends SIGKILL signal to the main process of the container
        # docker stop: send SIGTERM to let processes clean up
        docker kill "${group_number}""_ssh" &>/dev/null || true

        for ((i=0;i<n_routers;i++)); do
            router_i=(${routers[$i]})
            rname="${router_i[0]}"
            property1="${router_i[1]}"
            property2="${router_i[2]}"
            dname=$(echo $property2 | cut -s -d ':' -f 2)

            # kill router router
            docker kill "${group_number}""_""${rname}""router" &>/dev/null || true &

            # kill host
            if [[ ! -z "${dname}" ]]; then
                docker ps -q --filter "name=^${group_number}_${rname}host" | xargs -r docker kill &>/dev/null || true &

            fi

            # cleanup layer 2
            if [[ "${property2}" == *L2* ]];then
                # kill switches
                for ((l=0;l<n_l2_switches;l++)); do
                    switch_l=(${l2_switches[$l]})
                    l2name="${switch_l[0]}"
                    sname="${switch_l[1]}"
                    docker kill ${group_number}_L2_${l2name}_${sname} &>/dev/null || true &
                done

                # kill hosts
                for ((l=0;l<n_l2_hosts;l++)); do

                    host_l=(${l2_hosts[$l]})
                    hname="${host_l[0]}"
                    l2name="${host_l[2]}"

                    docker kill ${group_number}_L2_${l2name}_${hname} &>/dev/null || true &

                done
            fi

        done

        elif [ "${group_as}" = "IXP" ];then

        #kill IXP router
        docker kill "${group_number}""_IXP" &>/dev/null || true &

    fi

done

# allow parallel container temination
# ensure the script continues even if a container is not found
# &: run the command in the background
docker kill DNS &>/dev/null || true &
docker kill MEASUREMENT &>/dev/null || true &
docker kill MATRIX &>/dev/null || true &
docker kill WEB &>/dev/null || true &
docker kill PROXY &>/dev/null || true &

wait # wait for all background processes to finish
docker system prune -f --volumes  # remove all unused volumes
