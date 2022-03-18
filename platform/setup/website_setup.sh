#!/bin/bash
#
# Start the container that will run the webserver and all the tools
# related to it
#

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"
DOCKERHUB_USER="${2:-thomahol}"
source "${DIRECTORY}"/config/subnet_config.sh
source "${DIRECTORY}"/setup/_parallel_helper.sh

# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt
group_numbers=${#groups[@]}

docker_command_option=''

declare -A router_config_files

for ((k=0;k<group_numbers;k++)); do
    group_k=(${groups[$k]})
    group_number="${group_k[0]}"
    group_as="${group_k[1]}"
    group_config="${group_k[2]}"
    group_router_config="${group_k[3]}"
    group_layer2_switches="${group_k[5]}"
    group_layer2_hosts="${group_k[6]}"
    group_layer2_links="${group_k[7]}"

    if [ "${group_as}" != "IXP" ];then

        router_config_files[$group_router_config]=''

        readarray routers < "${DIRECTORY}"/config/$group_router_config
        n_routers=${#routers[@]}

        for ((i=0;i<n_routers;i++)); do
            router_i=(${routers[$i]})
            rname="${router_i[0]}"
            property1="${router_i[1]}"
            property2="${router_i[2]}"
            htype=$(echo $property2 | cut -d ':' -f 1)
            dname=$(echo $property2 | cut -d ':' -f 2)

            location=$(pwd ${DIRECTORY})"/groups/g"${group_number}"/"${rname}
            # echo "-v "${location}"/looking_glass.txt:/home/lg_G${group_number}_R${rname}.txt "

            docker_command_option=${docker_command_option}"-v "${location}"/looking_glass_json.txt:/tmp/lg_G${group_number}_${rname}.txt "                
        done
    fi
done

for key in "${!router_config_files[@]}"; do
    docker_command_option=${docker_command_option}" -v "$(pwd ${DIRECTORY})"/config/$key:/tmp/$key"
done

docker_command_option=${docker_command_option}" -v "$(pwd ${DIRECTORY})"/config/AS_config.txt:/tmp/AS_config.txt"
docker_command_option=${docker_command_option}" -v "$(pwd ${DIRECTORY})"/config/external_links_config.txt:/tmp/external_links_config.txt"
# docker_command_option=${docker_command_option}" -v "$(pwd ${DIRECTORY})"/config/external_links_config.txt:/tmp/external_links_config.txt"

if [ -f ${DIRECTORY}/config/external_links_config_students.txt ]; then
    docker_command_option=${docker_command_option}" -v "$(pwd ${DIRECTORY})"/config/external_links_config_students.txt:/tmp/external_links_config_students.txt"
fi

# echo $docker_command_option

docker_command_option=${docker_command_option}" -v "$(pwd ${DIRECTORY})"/groups/matrix/connectivity.txt:/tmp/connectivity.txt"

docker run -itd --net='none' --name="WEB" --cpus=2 \
    --pids-limit 100 \
    --hostname="g${group_number}-proxy" \
    --privileged \
    $docker_command_option "miniinterneteth/d_webserver"

# source "./setup/ovs-docker.sh"
# get_docker_pid 1_ZURIhost
# echo $DOCKER_PID
# ip link add web_host type veth peer name web_krill
# ip link set web_krill up
# ip address add 111.0.0.2/24 dev web_krill
# ip link set web_host netns $DOCKER_PID
# docker exec -it 1_ZURIhost ip link set web_host up
# docker exec -it 1_ZURIhost ip address add 111.0.0.1/24 dev web_host

#Make sure that UFA allows forwarding!

# docker exec 

# write in /etc/iproute2/rt_table: 100 sshtable

# ip rule add fwmark 0x1 lookup httptable
# ip route add default via 111.0.0.2 table httptable 