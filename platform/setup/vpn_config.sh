#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"

source "${DIRECTORY}"/config/variables.sh

if [ ${VPN_ENABLED} = false ]; then
	echo "VPN not enabled, skipping VPN setup"
	return 0 
fi

# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt
group_numbers=${#groups[@]}

# import wireguard scripts
source "${DIRECTORY}"/utils/vpn/interface_manager.sh

# loop through every existing router and set up a wireguard interface.
for ((k = 0; k < group_numbers; k++)); do
        group_k=(${groups[$k]})
        group_number="${group_k[0]}"
        group_as="${group_k[1]}"
        group_router_config="${group_k[3]}"

        if [ "${group_as}" != "IXP" ]; then
            readarray routers < "${DIRECTORY}"/config/$group_router_config
	    n_routers=${#routers[@]}
    	    for ((i = 0; i < n_routers; i++)); do
                router_i=(${routers[$i]})
                router_name="${router_i[0]}"
	    	
		create_if "${group_number}" "${router_name}"   
	    done		
        fi
done
