#!/bin/bash
#
# Start the container that will take regular snapshots of all configs.

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY=$(readlink -f $1)
source "${DIRECTORY}"/config/variables.sh

# Source directories.
DATADIR="${DIRECTORY}/groups"
HISTORYDIR="${DATADIR}/history"
mkdir -p "${HISTORYDIR}"
MATRIXDIR="${DATADIR}/matrix"

if $HISTORY_ENABLED; then
    echo "Starting history collector."
    # We need to give the container access to the docker socket so that it
    # can run the `save_config.sh` within each container and copy the files
    # out of it.
    docker run -itd --net='bridge' --name="HISTORY" --hostname="HISTORY" \
        -v "/var/run/docker.sock":/var/run/docker.sock \
        -v "${HISTORYDIR}":/home/history \
        -v "${MATRIXDIR}":/home/matrix \
        -e "OUTPUT_DIR=/home/history" \
        -e "MATRIX_DIR=/home/matrix" \
        -e "UPDATE_FREQUENCY=${HISTORY_UPDATE_FREQUENCY}" \
        -e "TIMEOUT=${HISTORY_TIMEOUT}" \
        -e "GIT_USER=${HISTORY_GIT_USER}" \
        -e "GIT_EMAIL=${HISTORY_GIT_EMAIL}" \
        -e "GIT_URL=${HISTORY_GIT_URL}" \
        -e "GIT_BRANCH=${HISTORY_GIT_BRANCH}" \
        -e "FORGET_BINARIES=${HISTORY_FORGET_BINARIES}" \
        "${DOCKERHUB_PREFIX}d_history" > /dev/null

    if $HISTORY_PAUSE_AFTER_START; then
        docker pause HISTORY
    fi
else
    echo "History collector is disabled."
    exit 0
fi