#!/bin/bash
#
# start matrix container
# setup links between groups and matrix container

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"
DOCKERHUB_USER="${2:-thomahol}"
source "${DIRECTORY}"/config/subnet_config.sh
source "${DIRECTORY}"/setup/_parallel_helper.sh

MATRIX_FREQUENCY=300  # seconds

# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt
group_numbers=${#groups[@]}

# Check if there is a MATRIX server
is_matrix=0
for ((k=0;k<group_numbers;k++)); do
    group_k=(${groups[$k]})
    group_as="${group_k[1]}"
    group_router_config="${group_k[3]}"

    if [ "${group_as}" != "IXP" ];then
        if grep -Fq "MATRIX" "${DIRECTORY}"/config/$group_router_config; then
            is_matrix=1
        fi
    fi
done

# Stop the script if there is no MATRIX server
if [[ "$is_matrix" -eq 0 ]]; then
    echo "There is no matrix container, skipping matrix_setup.sh"
else

    location="${DIRECTORY}"/groups/matrix/
    mkdir -p $location

    touch "$location"/destination_ips.txt
    touch "$location"/connectivity.txt
    touch "$location"/stats.txt

    # start matrix container
    docker run -itd --net='none' --name="MATRIX" --hostname="MATRIX" \
        --privileged --pids-limit 500 \
        --sysctl net.ipv4.icmp_ratelimit=0 \
        -v /etc/timezone:/etc/timezone:ro \
        -v /etc/localtime:/etc/localtime:ro \
        -v "${DIRECTORY}"/config/welcoming_message.txt:/etc/motd:rw \
        -v "${location}"/destination_ips.txt:/home/destination_ips.txt \
        -v "${location}"/connectivity.txt:/home/connectivity.txt \
        -v "${location}"/stats.txt:/home/stats.txt \
        -e "UPDATE_FREQUENCY=${MATRIX_FREQUENCY}" \
        "${DOCKERHUB_USER}/d_matrix" > /dev/null

    # Pause container to reduce load; can be unpaused on demand.
    docker pause MATRIX

    # cache the docker pid for ovs-docker.sh
    source ${DIRECTORY}/groups/docker_pid.map
    DOCKER_TO_PID['MATRIX']=$(docker inspect -f '{{.State.Pid}}' MATRIX)
    declare -p DOCKER_TO_PID > ${DIRECTORY}/groups/docker_pid.map

    echo -n "-- add-br matrix " >> "${DIRECTORY}"/groups/add_bridges.sh
    echo "ip link set dev matrix up" >> "${DIRECTORY}"/groups/ip_setup.sh

    for ((k=0;k<group_numbers;k++)); do
        group_k=(${groups[$k]})
        group_number="${group_k[0]}"
        group_as="${group_k[1]}"
        group_config="${group_k[2]}"
        group_router_config="${group_k[3]}"
        group_internal_links="${group_k[4]}"

        if [ "${group_as}" != "IXP" ];then

            readarray routers < "${DIRECTORY}"/config/$group_router_config
            readarray intern_links < "${DIRECTORY}"/config/$group_internal_links
            n_routers=${#routers[@]}
            n_intern_links=${#intern_links[@]}

            # find the ID of that router
            dest_router_id='None'
            for i in "${!routers[@]}"; do
            if [[ "${routers[$i]}" == *'MATRIX_TARGET'* ]]; then
                dest_router_id=$i;
            fi
            done

            if [ "$dest_router_id" != 'None' ]; then
                subnet="$(subnet_host_router "${group_number}" "$dest_router_id" host)"
                echo $group_number" "${subnet%/*} >> ${location}/destination_ips.txt

                for ((i=0;i<n_routers;i++)); do
                    router_i=(${routers[$i]})
                    rname="${router_i[0]}"
                    property1="${router_i[1]}"

                    if [ "${property1}" = "MATRIX"  ];then
                        subnet_bridge="$(subnet_router_MATRIX "${group_number}" "bridge")"
                            subnet_matrix="$(subnet_router_MATRIX "${group_number}" "matrix")"
                        subnet_group="$(subnet_router_MATRIX "${group_number}" "group")"

                        ./setup/ovs-docker.sh add-port matrix group_"${group_number}"  \
                        MATRIX --ipaddress="${subnet_matrix}"

                        mod=$((${group_number} % 100))
                        div=$((${group_number} / 100))

                        if [ $mod -lt 10 ];then
                            mod="0"$mod
                        fi
                        if [ $div -lt 10 ];then
                            div="0"$div
                        fi

                        ./setup/ovs-docker.sh add-port matrix matrix_"${group_number}" \
                        "${group_number}"_"${rname}"router --ipaddress="${subnet_group}" \
                        --macaddress="aa:11:11:11:"$div":"$mod

                        ./setup/ovs-docker.sh connect-ports matrix \
                        group_"${group_number}" MATRIX \
                        matrix_"${group_number}" "${group_number}"_"${rname}"router
                    fi
                done
            fi
        fi
    done

    wait
fi

