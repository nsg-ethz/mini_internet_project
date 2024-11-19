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
DIRECTORY=$(cd `dirname $0` && cd ../..  && pwd)

# Path to groups folder
groups_directory="${DIRECTORY}"/groups/

source "${DIRECTORY}"/config/variables.sh
source "${DIRECTORY}"/groups/docker_pid.map

# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt

# Gets the container name of a router
get_container_name() {
	echo "${1}_${2}router"
}

# Gets the PID of a container
get_container_pid() {
	echo "${DOCKER_TO_PID[$(get_container_name $1 $2)]}"
}

# Returns the port that this container is allowed to use
get_port() {
	# Read router configuration file
	group_k=(${groups[$1-1]})	
	group_router_config="${group_k[3]}"
	
	# Find the line with the corresponding router
	router_number=$(grep -n "$2" "${DIRECTORY}"/config/$group_router_config | awk -F: '{print $1}')

	# Calculate port number
	echo "$((10000 + $1 + 1000*$router_number))"
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
	docker_output=$(docker exec "$(get_container_name $1 $2)" ip link show vpn up)
	if [ -n "$docker_output" ]; then
		echo 1
	else
    		echo 0
	fi
}


# Creates a new interface for group $1, connected to router $2
create_if() {
	if [[ $(check_if_exists $1 $2 ) == 1 ]]; then
		echo "Error: A wireguard interface already exists!"
		exit 1
	fi

	path_to_file="${DIRECTORY}"/groups/g"$1"/"$2"/wireguard

	# Generate keys
	private_key=$(wg genkey)
        public_key=$(echo "${private_key}" | wg pubkey)
	listen_port=$(get_port $1 $2)

	# TODO: function to get ip address
	ip_address="3.1.0.1/24"
	

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

# Create a peer
create_wg_peer() { 
	path_to_file="${DIRECTORY}"/groups/g"$1"/"$2"/wireguard/	
	
	# TODO: get free peer ip
	wg_peer_ip="3.1.0.2/32"
        wg_subnet="0.0.0.0/0"
                
        # TODO: Find next free peer number
        filename="peer1.conf"                                                                        
	listen_port=$(get_port $1 $2)	
       
	# Generate Keypair
        private_key=$(wg genkey)                                                                     
        public_key=$(echo "${private_key}" | wg pubkey)                                              
        
        # Add new peer to interface                                                                  
        docker exec -u root "$(get_container_name $1 $2)" wg set vpn peer ${public_key} persistent-keepalive 25 allowed-ips ${wg_peer_ip}
        
	# Update interface configuration file
	printf "[Peer]\nPublicKey=%s\nAllowedIPs=%s\nPersistentKeepalive=25\n\n" ${public_key} ${wg_peer_ip} | tee -a "$path_to_file"/interface.conf > /dev/null
		
        # Create peer configuration file                                                             
        printf "[Interface]\nPrivateKey=%s\nAddress=%s\n\n" ${private_key} ${wg_peer_ip} | tee "$path_to_file"/${filename} > /dev/null
        printf "[Peer]\nPublicKey=%s\nAllowedIPs=%s\nEndpoint=%s:%s\nPersistentKeepalive=25\n\n" $(cat "$path_to_file"interface.pubkey) ${wg_subnet} ${SSH_URL} ${listen_port} | tee -a "$path_to_file"/"${filename}" > /dev/null
}    
