#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"

source "${DIRECTORY}"/utils/vpn/interface_manager.sh

delete_all_ifs 
