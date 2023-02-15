#!/bin/bash
#
# delete bridge to ssh container
# delete bridges between group and group container

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"
source "${DIRECTORY}"/config/subnet_config.sh

docker kill irrd_redis &>/dev/null || true &
docker kill irrd_postgres &>/dev/null || true &

if grep -q "irrd" "${DIRECTORY}"/config/AS_config.txt; then
    ip link del irrd_webserver &>/dev/null || true &
fi
