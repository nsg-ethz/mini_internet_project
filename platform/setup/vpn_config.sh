#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"

# Check if user has su rights
if [ $USER != root ] ; then
        echo "script needs to be executed with superuser rights!";
        exit 1
fi

source "${DIRECTORY}"/config/variables.sh
source "${DIRECTORY}"/config/subnet_config.sh

if [ ${VPN_ENABLED} = false ]; then
	echo "VPN not enabled, skipping VPN setup"
	exit 0 
fi

# Check if wireguard is installed.
if command -v wg > /dev/null 2>&1; then 
	echo "WireGuard is already installed. Proceeding."
else 
	echo "WireGuard is not installed. Installing WireGuard."
	
	# Install wireguard
	sudo apt update && sudo apt install -y wireguard-tools

	
	if command -v wg > /dev/null 2>&1; then 
		echo "WireGuard sucessfully installed. Proceeding."
	else 
		echo "WireGuard installation failed. Skipping VPN setup."
		exit 0
	fi
fi

# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt
group_numbers=${#groups[@]}

# import wireguard scripts
source "${DIRECTORY}"/utils/vpn/interface_manager.sh

echo "[" >> "${DIRECTORY}"/groups/"${VPN_PASSWD_FILE}"

# loop through every existing router and set up a wireguard interface.
for ((k = 0; k < group_numbers; k++)); do
        group_k=(${groups[$k]})
        group_number="${group_k[0]}"
        group_as="${group_k[1]}"
        group_router_config="${group_k[3]}"
	
        if [ "${group_as}" != "IXP" ]; then
            if [[ ${VPN_WEBSITE_ENABLED} == true ]]; then
		echo '{"group_id":'${group_number}', "username":"Group '${group_number}'", "password":"'$(openssl rand -base64 12)'"},' >> "${DIRECTORY}"/groups/"${VPN_PASSWD_FILE}"
	    fi
		
	    readarray routers < "${DIRECTORY}"/config/$group_router_config
	    n_routers=${#routers[@]}
    	    for ((i = 0; i < n_routers; i++)); do
                router_i=(${routers[$i]})
		router_number=($i + 1)
                router_name="${router_i[0]}"
		
		interface_ip=$(subnet_host_router "${group_number}" "${router_number}" vpn_interface)
		create_if "${group_number}" "${router_name}" "${interface_ip}"> /dev/null
		
		for ((client_no = 1; client_no <= "${VPN_NO_CLIENTS}"; client_no++)); do
			peer_ip=$(subnet_host_router "${group_number}" "${router_number}" vpn_peer "${client_no}")
			if [[ ${client_no} > 1 ]]; then
				peer_name="Client${client_no}"
			else
				peer_name=Peer
			fi
			create_wg_peer "${group_number}" "${router_name}" "${peer_name}" "${peer_ip}"
			
			# Configure OSPF
			docker exec -it "${group_number}_${router_name}router" vtysh -c "conf t" -c "router ospf" -c "network ${interface_ip} area 0"
		done
	    done		
        fi
	echo "Configured VPN of group ${group_number} "
done

# Remove trailing comma and close the list
sed -i '${s/,$//}' "${DIRECTORY}"/groups/"${VPN_PASSWD_FILE}"
echo "]" >> "${DIRECTORY}"/groups/"${VPN_PASSWD_FILE}"
