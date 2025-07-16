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

DIRECTORY=$(readlink -f $1)
source "${DIRECTORY}"/config/variables.sh

# Source directories.
DATADIR="$(pwd ${DIRECTORY})/groups"
CONFIGDIR="$(pwd ${DIRECTORY})/config"

# Directory for server config.
mkdir -p "${DATADIR}/webserver"
CONFIGFILE="${DATADIR}/webserver/config.py"
LETSENCRYPT="${DATADIR}/webserver/letsencrypt"

# Directories inside the container.
DATADIR_SERVER='/server/data'
CONFIGDIR_SERVER='/server/configs'

source "${DIRECTORY}"/config/subnet_config.sh
source "${DIRECTORY}"/setup/_parallel_helper.sh

# TLS and LetsEncrypt
if [ ! -z "$WEBSERVER_ACME_MAIL" ] && [ ! -z "$WEBSERVER_HOSTNAME" ] && [ "$WEBSERVER_HOSTNAME" != "localhost" ] ; then
    IFS=" " read -ra TLSCONF <<< "\
    --entrypoints.web.http.redirections.entrypoint.to=websecure \
    --entrypoints.web.http.redirections.entrypoint.scheme=https \
    --entrypoints.web.http.redirections.entrypoint.permanent=true \
    --certificatesresolvers.project_resolver.acme.tlschallenge=true \
    --certificatesresolvers.project_resolver.acme.email=${WEBSERVER_ACME_MAIL} \
    --certificatesresolvers.project_resolver.acme.storage=/letsencrypt/acme.json \
    --entrypoints.websecure.http.tls.certresolver=project_resolver \
    --entrypoints.krill.http.tls.certresolver=project_resolver"
    KRILL_SCHEME="https"
else
    TLSCONF=""
    KRILL_SCHEME="http"
fi

# Write the webserver config file
cat > "$CONFIGFILE" << EOM
LOCATIONS = {
    "config_directory": "${CONFIGDIR_SERVER}",
    'as_config': "${CONFIGDIR_SERVER}/AS_config.txt",
    "as_connections_public": "${CONFIGDIR_SERVER}/aslevel_links_students.txt",
    "as_connections": "${CONFIGDIR_SERVER}/aslevel_links.txt",
    'groups': '${DATADIR_SERVER}',
    "matrix": "${DATADIR_SERVER}/matrix/connectivity.txt",
    "matrix_stats": "${DATADIR_SERVER}/matrix/stats.txt",
}
KRILL_URL="${KRILL_SCHEME}://{hostname}:${WEBSERVER_PORT_KRILL}/index.html"
BASIC_AUTH_USERNAME = 'admin'
BASIC_AUTH_PASSWORD = 'admin'
BACKGROUND_WORKERS = True
HOST = '0.0.0.0'
PORT = 8000
EOM

# First start the web container, adding labels for the traefik proxy.
# We only have one webserver; traffic for any hostname will go to it.
# NOTE: Can we define all dynamic labels for krill here?
docker run -itd --name="WEB" --cpus=2 \
    --network="bridge" -p 8000:8000 \
    --pids-limit 100 \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v ${DATADIR}:${DATADIR_SERVER} \
    -v ${CONFIGDIR}:${CONFIGDIR_SERVER} \
    -v ${CONFIGFILE}:/server/config.py \
    -e SERVER_CONFIG=/server/config.py \
    -e TZ=${WEBSERVER_TZ} \
    -l traefik.enable=true \
    -l traefik.http.routers.web.entrypoints=web \
    -l traefik.http.routers.websecure.entrypoints=websecure \
    --hostname="web" \
    --privileged \
    "${DOCKERHUB_PREFIX}d_webserver" > /dev/null

# Next start the proxy
# Setup based on the following tutorials:
# https://doc.traefik.io/traefik/user-guides/docker-compose/basic-example/
# https://doc.traefik.io/traefik/user-guides/docker-compose/acme-http/
# To enable the dashboard for debugging, add -p 8080:8080
# and the command "--api.insecure=true" (at the very end).
# The dashboard is then available at http://localhost:8080/dashboard/
# If anything goes wrong, add "--log.level=DEBUG" to enable logging,
# and then use "sudo docker logs PROXY" to see the logs.
docker run -d --name='PROXY' --network="bridge" \
    -p ${WEBSERVER_PORT_HTTP}:${WEBSERVER_PORT_HTTP} \
    -p ${WEBSERVER_PORT_HTTPS}:${WEBSERVER_PORT_HTTPS} \
    -p ${WEBSERVER_PORT_KRILL}:${WEBSERVER_PORT_KRILL} \
    -v "/var/run/docker.sock:/var/run/docker.sock:ro" \
    -v ${LETSENCRYPT}:/letsencrypt \
    --privileged \
    traefik:v2.6 \
    "--providers.docker=True" \
    "--providers.docker.network=bridge" \
    "--providers.docker.exposedbydefault=false" ${TLSCONF[@]} \
    "--providers.docker.defaultRule=Host(\"${WEBSERVER_HOSTNAME}\")" \
    "--entrypoints.web.address=:${WEBSERVER_PORT_HTTP}" \
    "--entrypoints.websecure.address=:${WEBSERVER_PORT_HTTPS}" \
    "--entrypoints.krill.address=:${WEBSERVER_PORT_KRILL}" > /dev/null
