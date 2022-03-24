#!/bin/bash
#
# Start the containers that will run the webserver and all the tools
# related to it
#
# Concretely, we use two containers
# - WEB: the webserver container delivering the pages.
# - PROXY: a container running the reverse proxy traefik, which takes care
#          of letsencrypt certificates, too.
#
# TODO:
# - We could make HTTPS optional.
# - How to make hostname and mail easy to configure?

set -o errexit
set -o pipefail
set -o nounset

# Directories on host.
DIRECTORY="$1"
OUTPUT_DIRECTORY="$(pwd ${DIRECTORY})/groups"
# Directories in container
DATADIR='/server/data'
CONFIGDIR='/server/configs'

# Ports for the webserver and krill on the host.
# (must be publicly available)
TZ="Europe/Zurich"

HOSTNAME="duvel.ethz.ch"  # required for https
SERVER_PORT_HTTP="80"
SERVER_PORT_HTTPS="443"
KRILL_PORT="3080"

# Letsencrypt parameters
ACME_MAIL="nsg@ethz.ch"


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
BACKGROUND_WORKERS = True
HOST = '0.0.0.0'
PORT = 8000
EOM

docker_command_option=${docker_command_option}" -v ${OUTPUT_DIRECTORY}/webserver_config.py:/server/config.py"

# First start the web container, adding labels for the traefik proxy.
# We only have one webserver; traffic for any hostname will go to it.
docker run -itd --name="WEB" --cpus=2 \
    --network bridge -p 8000:8000 \
    --pids-limit 100 \
    -e SERVER_CONFIG=/server/config.py \
    -e TZ=${TZ} \
    -l traefik.enable=true \
    -l traefik.http.routers.WEB.rule="Host(\"${HOSTNAME}\")" \
    -l traefik.http.routers.WEB.entrypoints=web \
    -l traefik.http.routers.WEB.entrypoints=websecure \
    -l traefik.http.routers.WEB.tls.certresolver=WEBresolver \
    --hostname="web" \
    --privileged \
    $docker_command_option "miniinterneteth/d_webserver"

# Next start the proxy
# Setup based on the following tutorials:
# https://doc.traefik.io/traefik/user-guides/docker-compose/basic-example/
# https://doc.traefik.io/traefik/user-guides/docker-compose/acme-http/
# To enable the dashboard for debugging, add -p 8080:8080
# and the command "--api.insecure=true" (at the very end).
docker run -d --name='PROXY' \
    --network bridge \
    -p ${SERVER_PORT_HTTP}:${SERVER_PORT_HTTP} \
    -p ${SERVER_PORT_HTTPS}:${SERVER_PORT_HTTPS} \
    -p 8080:8080 \
    -v "/var/run/docker.sock:/var/run/docker.sock:ro" \
    -v ${OUTPUT_DIRECTORY}/letsencrypt:/letsencrypt \
    --privileged \
    traefik:v2.6 \
    "--providers.docker=True"\
    "--providers.docker.exposedbydefault=false" \
    "--entrypoints.web.address=:${SERVER_PORT_HTTP}" \
    "--entrypoints.websecure.address=:${SERVER_PORT_HTTPS}" \
    "--entrypoints.web.http.redirections.entrypoint.to=websecure" \
    "--entrypoints.web.http.redirections.entrypoint.scheme=https" \
    "--certificatesresolvers.WEBresolver.acme.tlschallenge=true" \
    "--certificatesresolvers.WEBresolver.acme.storage=/letsencrypt/acme.json" \
    "--certificatesresolvers.myresolver.acme.email=${ACME_MAIL}" \
    "--api.insecure=true" \
