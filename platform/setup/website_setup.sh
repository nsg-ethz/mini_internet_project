#!/bin/bash
#
# Start the container that will run the webserver and all the tools
# related to it
#

set -o errexit
set -o pipefail
set -o nounset

# Directories on host.
DIRECTORY="$1"
OUTPUT_DIRECTORY="$(pwd ${DIRECTORY})/groups"
# Directories in container
DATADIR='/server/data'
CONFIGDIR='/server/configs'


KRILL_PORT="3080"
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

            # Copy both the text and json looking glass output.
            files=("looking_glass.txt" "looking_glass_json.txt")
            for filename in ${files[*]}; do
                docker_command_option=${docker_command_option}"-v "${location}"/${filename}:${DATADIR}/g${group_number}/${rname}/${filename} "
            done                  
        done
    fi
done

for key in "${!router_config_files[@]}"; do
    docker_command_option=${docker_command_option}" -v "$(pwd ${DIRECTORY})"/config/$key:${CONFIGDIR}/$key"
done

docker_command_option=${docker_command_option}" -v "$(pwd ${DIRECTORY})"/config/AS_config.txt:${CONFIGDIR}/AS_config.txt"
docker_command_option=${docker_command_option}" -v "$(pwd ${DIRECTORY})"/config/external_links_config.txt:${CONFIGDIR}/external_links_config.txt"

if [ -f ${DIRECTORY}/config/external_links_config_students.txt ]; then
    docker_command_option=${docker_command_option}" -v "$(pwd ${DIRECTORY})"/config/external_links_config_students.txt:${CONFIGDIR}/external_links_config_students.txt"
fi

# echo $docker_command_option

docker_command_option=${docker_command_option}" -v "$(pwd ${DIRECTORY})"/groups/matrix/connectivity.txt:${DATADIR}/connectivity.txt"

# Write the webserver config file
cat > "$OUTPUT_DIRECTORY/webserver_config.py" << EOM
LOCATIONS = {
    "config_directory": "${CONFIGDIR}",
    'as_config': "${CONFIGDIR}/AS_config.txt",
    "as_connections_public": "${CONFIGDIR}/external_links_config_students.txt",
    "as_connections": "${CONFIGDIR}/external_links_config.txt",
    'groups': '${DATADIR}',
    "matrix": "${DATADIR}/connectivity.txt"
}
KRILL_URL="http://{hostname}:${KRILL_PORT}/index.html"
BASIC_AUTH_USERNAME = 'admin'
BASIC_AUTH_PASSWORD = 'admin'
HOST = '0.0.0.0'
PORT = 8000
EOM

docker_command_option=${docker_command_option}" -v ${OUTPUT_DIRECTORY}/webserver_config.py:/server/config.py"

docker run -itd --name="WEB" --cpus=2 \
    --network host \
    --pids-limit 100 \
    -e SERVER_CONFIG=/server/config.py \  # Path to config file.
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