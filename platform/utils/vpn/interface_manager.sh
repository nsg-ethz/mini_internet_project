#!/bin/bash

# This script can manage wireguard interfaces of mini-internet containers.
# We only ever manage wireguard interfaces attached to routers

set -o errexit # exit on error
set -o pipefail # catch errors in pipelines
set -o nounset # exit on undeclared variable

# Check if user has su rights
if [ $USER != root ] ; then 
	echo "script needs to be executed with superuser rights!"; 
	exit 1
fi

# Absolute path to platform directory
DIRECTORY=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && cd ../.. && pwd )

# Path to groups folder
groups_directory="${DIRECTORY}"/groups/

source "${DIRECTORY}"/config/variables.sh
source "${DIRECTORY}"/groups/docker_pid.map

# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt
group_numbers=${#groups[@]}

# Gets the container name of a router
get_container_name() {
	echo "${1}_${2}router"
}

# Gets the PID of a container
get_container_pid() {
	echo "${DOCKER_TO_PID[$(get_container_name $1 $2)]}"
}

get_router_number() {                                                                                          
        router_number=-1
        # Read AS config file, to find the router config file of group number $1                      
        for ((k = 0; k < ${#groups[@]}; k++)); do                                                     
                group_k=(${groups[k]})                                                                
                if [[ ${group_k[0]} == $1 ]]; then                                                    
                        # found our group                                                             
                        group_router_config_file="${group_k[3]}"                                      
                        
                        # Find all lines with the corresponding router                                
                        router_numbers=$(grep -n "$2" "${DIRECTORY}"/config/$group_router_config_file | awk -F: '{print $1}')  
                        # Only take the first appearance                                              
                        router_number=${router_numbers:0:1}                                           
                fi      
        done                                                                                          
                                                                                                      
        if [[ router_number == -1 ]]; then                                                               
                echo "Error, couldn't find router $2 in  group $1"                                           
                exit 1                                                                                
        else
                echo "$router_number"                                                                   
        fi                                                                                            
}   


# Returns the port that this container is allowed to use
get_port() {
	router_number=$(get_router_number "$1" "$2")

	# Calculate port number
        port_number="$((10000 + $1 + 1000*${router_number}))"
	
	echo "$port_number"
}

# Check if a wireguard interface exists for $1 = GroupNumber and $2 = RouterName
# Example "check_if_exists 3 MUNI" checks if the MUNI router of group 3 has a wireguard interface.
check_if_exists() {
	path_to_file="${DIRECTORY}"/groups/g"$1"/"$2"/wireguard/interface.conf
	if [ -f "$path_to_file" ]; then
		echo 1
	else
		echo 0
	fi
}

# Check if a wireguard interface is up and running ($1 = GroupNumber and $2 = RouterName)
# Example "check_if_up 3 MUNI"
check_if_up() {
	docker_output=$(docker exec "$(get_container_name $1 $2)" sh -c "ip link show vpn up > /dev/null 2>&1 && echo 1 || echo 0")
	echo "${docker_output}"
}


# Creates a new interface for group $1, connected to router $2. $3 = IP Address
create_if() {
	if [[ $(check_if_exists $1 $2 ) == 1 ]]; then
		echo "Error: A wireguard interface already exists!"
		return 0 
	fi

	path_to_file="${DIRECTORY}"/groups/g"$1"/"$2"/wireguard

	# Generate keys
	private_key=$(wg genkey)
        public_key=$(echo "${private_key}" | wg pubkey)
	
	listen_port=$(get_port $1 $2)
	
	router_number=$(get_router_number "$1" "$2")
	ip_address=${3}

	# Save configuration and public key
	printf "[Interface]\nPrivateKey=%s\nListenPort=%s\n\n" ${private_key} ${listen_port} | tee "${path_to_file}"/interface.conf > /dev/null
	echo "${public_key}" | tee "${path_to_file}"/interface.pubkey > /dev/null

	PID=$(get_container_pid $1 $2)

	# Add wireguard interface	
	ip link add vpn type wireguard
	
	# Move interface to the container
	ip link set vpn netns "${PID}"

	# Configure interface
	nsenter --net=/proc/"${PID}"/ns/net ip address add "${ip_address}" dev vpn 
	docker exec -u root "$(get_container_name $1 $2)" wg setconf vpn /etc/wireguard/interface.conf
	
	nsenter --net=/proc/"${PID}"/ns/net ip link set vpn up
	
	# Set up rate limits
	if [[ ${VPN_LIMIT_ENABLED} == true  ]]; then
		nsenter --net=/proc/"${PID}"/ns/net tc qdisc add dev vpn root tbf rate ${VPN_LIMIT_RATE} burst ${VPN_LIMIT_BURST} latency ${VPN_LIMIT_LATENCY}
	fi

	# Set firewall exception	
	ufw allow "${listen_port}" > /dev/null
}

# Deletes an interface
delete_if() {
	PID=$(get_container_pid $1 $2)
        path_to_file="${DIRECTORY}"/groups/g"$1"/"$2"/wireguard
	listen_port=$(get_port $1 $2)

	# Delete interface if it exists
	if [[ $(check_if_up $1 $2 ) == 1 ]]; then
        	# No need to save config, because we delete interface
		nsenter --net=/proc/"${PID}"/ns/net ip link del vpn
	fi

	# Delete file if it exists
	if [[ $(check_if_exists $1 $2 ) == 1 ]]; then
		rm "${path_to_file}"/*
	fi

	# Remove firewall exception
	ufw delete allow "${listen_port}" > /dev/null
}

delete_all_ifs() {
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
	
			echo "Deleting wg interface ${group_number}-${router_name}"
			delete_if "${group_number}" "${router_name}"	
		    done		
		fi
	done
}

# Create a peer with $1 = GroupNumber, $2 = RouterName,$3 = PeerName, $4 = IPAddress
# Example: create_wg_peer 3 ZURI leos_device "3.1.0.2/32"
create_wg_peer() { 
	path_to_file="${DIRECTORY}"/groups/g"$1"/"$2"/wireguard/        
        filename="${3}.peer"                                                                        
	
	if [ -f "${path_to_file}"/"${filename}" ]; then
		# echo "Peer ${3} already exists! (${1}-${2})"
		return 0
	fi	

	listen_port=$(get_port $1 $2)	
	dns="198.${1}.0.2"
	wg_peer_ip="$4"
        wg_subnet="0.0.0.0/0"
	
       
	# Generate Keypair
        private_key=$(wg genkey)                                                                     
        public_key=$(echo "${private_key}" | wg pubkey)                                              
        
        # Add new peer to interface                                                                  
        docker exec -u root "$(get_container_name $1 $2)" wg set vpn peer ${public_key} persistent-keepalive 25 allowed-ips ${wg_peer_ip}
        
	# Update interface configuration file
	printf "[Peer]\nPublicKey=%s\nAllowedIPs=%s\nPersistentKeepalive=25\n\n" ${public_key} ${wg_peer_ip} | tee -a "$path_to_file"/interface.conf > /dev/null
		
        # Create peer configuration file                                                             
        # Add interface section
	printf "[Interface]\nPrivateKey=%s\nAddress=%s\n" ${private_key} ${wg_peer_ip} | tee "$path_to_file"/${filename} > /dev/null
	if [[ ${VPN_DNS_ENABLED} == true ]]; then
		printf "DNS=%s\n" ${dns}| tee -a "$path_to_file"/${filename} > /dev/null
	fi
	
	# Add peer section
	printf "\n[Peer]\nPublicKey=%s\nAllowedIPs=%s\nEndpoint=%s:%s\nPersistentKeepalive=25\n\n" $(cat "$path_to_file"interface.pubkey) ${wg_subnet} ${SSH_URL} ${listen_port} | tee -a "$path_to_file"/"${filename}" > /dev/null
}
