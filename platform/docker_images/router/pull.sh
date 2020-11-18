#!/bin/bash
#
# Pull the latest version of all the docker images used in the mini-Internet

set -o errexit
set -o pipefail
set -o nounset

docker pull thomahol/d_router
