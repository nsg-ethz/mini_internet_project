#!/bin/bash
#
# setup the IRRd environment in case it is used

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"
DOCKERHUB_USER="$2"

source "${DIRECTORY}"/config/subnet_config.sh
source "${DIRECTORY}"/setup/ovs-docker.sh

# check if IRRd used
if grep -q "irrd" "${DIRECTORY}"/config/AS_config.txt; then

	# Generate a override password and add it to the container
	passwd="$(openssl rand -hex 8)"
	echo "${passwd}" >> "${DIRECTORY}"/groups/irrd_override_password.txt

	salt="$(openssl rand -hex 4)"
	hashed_pw=$(openssl passwd -1 -salt "${salt}" "${passwd}")
	docker exec -t 2_ZURIhost sed -i "s~override_password:~override_password: ${hashed_pw}~g" /etc/irrd.yaml

	# use bridge from AS2-host
	br_name="2-host"

	# start a redis container
	docker run -itd --net=none --name="irrd_redis" \
	-v /etc/timezone:/etc/timezone:ro \
	-v /etc/localtime:/etc/localtime:ro \
	"${DOCKERHUB_USER}/d_irrd_redis"

	# start a postgres container
	docker run -itd --net=none --name="irrd_postgres" \
	-v /etc/timezone:/etc/timezone:ro \
	-v /etc/localtime:/etc/localtime:ro \
	"${DOCKERHUB_USER}/d_irrd_postgres"

	# Add PIDs to pidfile
	source "${DIRECTORY}/groups/docker_pid.map"
	DOCKER_TO_PID["irrd_postgres"]=$(docker inspect -f '{{.State.Pid}}' irrd_postgres)
	DOCKER_TO_PID["irrd_redis"]=$(docker inspect -f '{{.State.Pid}}' irrd_redis)
	declare -p DOCKER_TO_PID > "${DIRECTORY}/groups/docker_pid.map"

	echo "# IRRd to webserver setup" >> "${DIRECTORY}"/groups/ip_setup.sh
	echo "ip link add irrd_postgres type veth peer name postgres_irrd" >> "${DIRECTORY}"/groups/ip_setup.sh
	echo "ip link add irrd_redis type veth peer name redis_irrd" >> "${DIRECTORY}"/groups/ip_setup.sh

	# Get IP addresses
	redis_ip="$(subnet_irrd "redis" "db")"
	redis_host_ip="$(subnet_irrd "redis" "client")"
	postgres_ip="$(subnet_irrd "postgres" "db")"
	postgres_host_ip="$(subnet_irrd "postgres" "client")"

	# Set network config for the IRRd
	get_docker_pid 2_ZURIhost
	echo "PID=$DOCKER_PID" >> "${DIRECTORY}"/groups/ip_setup.sh
	echo "create_netns_link" >> "${DIRECTORY}"/groups/ip_setup.sh
	echo "ip link set netns \$PID dev irrd_postgres" >> "${DIRECTORY}"/groups/ip_setup.sh
	echo "ip link set netns \$PID dev irrd_redis" >> "${DIRECTORY}"/groups/ip_setup.sh
	echo "ip netns exec \$PID ip a add "${redis_host_ip}" dev irrd_redis" >> "${DIRECTORY}"/groups/ip_setup.sh
	echo "ip netns exec \$PID ip link set dev irrd_redis up" >> "${DIRECTORY}"/groups/ip_setup.sh
	echo "ip netns exec \$PID ip a add "${postgres_host_ip}" dev irrd_postgres" >> "${DIRECTORY}"/groups/ip_setup.sh
	echo "ip netns exec \$PID ip link set dev irrd_postgres up" >> "${DIRECTORY}"/groups/ip_setup.sh

	# Set network config for the Postgres
	get_docker_pid irrd_postgres
	echo "PID=$DOCKER_PID" >> "${DIRECTORY}"/groups/ip_setup.sh
	echo "create_netns_link" >> "${DIRECTORY}"/groups/ip_setup.sh
	echo "ip link set netns \$PID dev postgres_irrd" >> "${DIRECTORY}"/groups/ip_setup.sh
	echo "ip netns exec \$PID ip a add "${postgres_ip}" dev postgres_irrd" >> "${DIRECTORY}"/groups/ip_setup.sh
	echo "ip netns exec \$PID ip link set dev postgres_irrd up" >> "${DIRECTORY}"/groups/ip_setup.sh

	# Set network config for the Redis
	get_docker_pid irrd_redis
	echo "PID=$DOCKER_PID" >> "${DIRECTORY}"/groups/ip_setup.sh
	echo "create_netns_link" >> "${DIRECTORY}"/groups/ip_setup.sh
	echo "ip link set netns \$PID dev redis_irrd" >> "${DIRECTORY}"/groups/ip_setup.sh
	echo "ip netns exec \$PID ip a add "${redis_ip}" dev redis_irrd" >> "${DIRECTORY}"/groups/ip_setup.sh
	echo "ip netns exec \$PID ip link set dev redis_irrd up" >> "${DIRECTORY}"/groups/ip_setup.sh

fi
