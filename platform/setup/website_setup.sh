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

# Hostname and ACME mail for letsencrypt.
# You need to specify a hostname different to "localhost" and an email for
# LetsEncrypt to be enabled.
HOSTNAME="duvel.ethz.ch"
ACME_MAIL="nsg@ethz.ch"

# Hostname and ports for the webserver and krill on the host.
# (must be publicly available)
SERVER_PORT_HTTP="80"
SERVER_PORT_HTTPS="443"
KRILL_PORT="3080"

TZ="Europe/Zurich"

DOCKERHUB_USER="${2:-thomahol}"
source "${DIRECTORY}"/config/subnet_config.sh
source "${DIRECTORY}"/setup/_parallel_helper.sh

# Write the webserver config file
cat > "$CONFIGFILE" << EOM
LOCATIONS = {
    "config_directory": "${CONFIGDIR_SERVER}",
    'as_config': "${CONFIGDIR_SERVER}/AS_config.txt",
    "as_connections_public": "${CONFIGDIR_SERVER}/external_links_config_students.txt",
    "as_connections": "${CONFIGDIR_SERVER}/external_links_config.txt",
    'groups': '${DATADIR_SERVER}',
    "matrix": "${DATADIR_SERVER}/matrix/connectivity.txt"
}
KRILL_URL="http://{hostname}:${KRILL_PORT}/index.html"
BASIC_AUTH_USERNAME = 'admin'
BASIC_AUTH_PASSWORD = 'admin'
BACKGROUND_WORKERS = True
HOST = '0.0.0.0'
PORT = 8000
EOM

# TLS and LetsEncrypt
if [ ! -z "$HOSTNAME" ] && [ "$HOSTNAME" != "localhost" ] ; then
    IFS=" " read -ra TLSCONF <<< "\
    --entrypoints.websecure.address=:${SERVER_PORT_HTTPS} \
    --entrypoints.web.http.redirections.entrypoint.to=websecure \
    --entrypoints.web.http.redirections.entrypoint.scheme=https \
    --entrypoints.web.http.redirections.entrypoint.permanent=true \
    --entrypoints.krill.http.redirections.entrypoint.scheme=https \
    --entrypoints.krill.http.redirections.entrypoint.permanent=true \
    --certificatesresolvers.project_resolver.acme.tlschallenge=true \
    --certificatesresolvers.project_resolver.acme.email=${ACME_MAIL} \
    --certificatesresolvers.project_resolver.acme.storage=/letsencrypt/acme.json \
    --entrypoints.web.http.tls.certresolver=project_resolver \
    --entrypoints.krill.http.tls.certresolver=project_resolver"
    IFS=" " read -ra SAFEENTRY <<< "\
    -l traefik.http.routers.web.entrypoints=websecure"
else
    TLSCONF=""
    SAFEENTRY=""
fi

# First start the web container, adding labels for the traefik proxy.
# We only have one webserver; traffic for any hostname will go to it.
# NOTE: Can we define all dynamic labels for krill here?
docker run -itd --name="WEB" --cpus=2 \
    --network bridge -p 8000:8000 \
    --pids-limit 100 \
    -v ${DATADIR}:${DATADIR_SERVER} \
    -v ${CONFIGDIR}:${CONFIGDIR_SERVER} \
    -v ${CONFIGFILE}:/server/config.py \
    -e SERVER_CONFIG=/server/config.py \
    -e TZ=${TZ} \
    -l traefik.enable=true \
    -l traefik.http.routers.web.entrypoints=web ${SAFEENTRY[@]}\
    --hostname="web" \
    --privileged \
    "miniinterneteth/d_webserver"

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
    -v "/var/run/docker.sock:/var/run/docker.sock:ro" \
    -v ${LETSENCRYPT}:/letsencrypt \
    --privileged \
    traefik:v2.6 \
    "--providers.docker=True"\
    "--providers.docker.exposedbydefault=false" \
    "--providers.docker.defaultRule=Host(\"${HOSTNAME}\")" \
    "--entrypoints.web.address=:${SERVER_PORT_HTTP}" \
    "--entrypoints.krill.address=:${KRILL_PORT}" \
    "${TLSCONF[@]}"
