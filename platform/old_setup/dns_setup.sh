#!/bin/bash
#
# start dns server container
# setup links between groups and dns server
# connect measurement container to dns server

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"
DOCKERHUB_USER="${2:-thomahol}"
source "${DIRECTORY}"/config/subnet_config.sh

# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt
group_numbers=${#groups[@]}

# Check if there is a DNS server
is_dns=0
for ((k=0;k<group_numbers;k++)); do
    group_k=(${groups[$k]})
    group_as="${group_k[1]}"
    group_router_config="${group_k[3]}"

    if [ "${group_as}" != "IXP" ];then
        if grep -Fq "DNS" "${DIRECTORY}"/config/$group_router_config; then
            is_dns=1
        fi
    fi
done

echo "#!/bin/bash" > "${DIRECTORY}"/groups/dns_routes.sh
echo "source \"${DIRECTORY}/setup/ovs-docker.sh\"" >> "${DIRECTORY}"/groups/dns_routes.sh
chmod +x "${DIRECTORY}"/groups/dns_routes.sh

# Stop the script if there is no DNS server
if [[ "$is_dns" -eq 0 ]]; then
    echo "There is no DNS server, skipping dns_setup.sh"
else
    # create dns container, copy files generated from dns_config.sh into the
    # container before starting it.
    docker create --net='none' --name="DNS" --hostname="DNS" --privileged \
        -v /etc/timezone:/etc/timezone:ro \
        -v /etc/localtime:/etc/localtime:ro \
        "${DOCKERHUB_USER}/d_dns"

    docker cp "${DIRECTORY}"/groups/dns/group_config DNS:/etc/bind/group_config > /dev/null
    docker cp "${DIRECTORY}"/groups/dns/zones DNS:/etc/bind/zones > /dev/null
    docker cp "${DIRECTORY}"/groups/dns/named.conf.local DNS:/etc/bind/named.conf.local > /dev/null
    docker cp "${DIRECTORY}"/groups/dns/named.conf.options DNS:/etc/bind/named.conf.options > /dev/null

    docker start DNS

    # cache the container pid for ovs-docker.sh
    source "${DIRECTORY}/groups/docker_pid.map"
    DOCKER_TO_PID["DNS"]=$(docker inspect -f '{{.State.Pid}}' DNS)
    declare -p DOCKER_TO_PID > "${DIRECTORY}/groups/docker_pid.map"
    source "${DIRECTORY}/setup/ovs-docker.sh"

    echo -n "-- add-br dns " >> "${DIRECTORY}"/groups/add_bridges.sh
    echo "ip link set dev dns up" >> "${DIRECTORY}"/groups/ip_setup.sh

    get_docker_pid DNS
    echo "PID=$DOCKER_PID" >> "${DIRECTORY}"/groups/dns_routes.sh
    echo "create_netns_link" >> "${DIRECTORY}"/groups/dns_routes.sh

    for ((k=0;k<group_numbers;k++)); do
        group_k=(${groups[$k]})
        group_number="${group_k[0]}"
        group_as="${group_k[1]}"
        group_config="${group_k[2]}"
        group_router_config="${group_k[3]}"

        if [ "${group_as}" != "IXP" ];then

            readarray routers < "${DIRECTORY}"/config/$group_router_config
            n_routers=${#routers[@]}

            for ((i=0;i<n_routers;i++)); do
                router_i=(${routers[$i]})
                rname="${router_i[0]}"
                property1="${router_i[1]}"

                if [ "${property1}" = "DNS"  ];then
                    # create bridge between dns and group
                    subnet_bridge="$(subnet_router_DNS "${group_number}" "bridge")"
                    subnet_dns="$(subnet_router_DNS "${group_number}" "dns")"
                    subnet_group="$(subnet_router_DNS "${group_number}" "group")"

                    ./setup/ovs-docker.sh add-port dns group_"${group_number}"  \
                      DNS --ipaddress="${subnet_dns}"
                    ./setup/ovs-docker.sh add-port dns dns_"${group_number}" \
                      "${group_number}"_"${rname}"router --ipaddress="${subnet_group}"

                    ./setup/ovs-docker.sh connect-ports dns \
                    group_"${group_number}" DNS \
                    dns_"${group_number}" "${group_number}"_"${rname}"router
                    echo "ip netns exec \$PID ip route add "${subnet_group%/*}" dev group_"${group_number}" " >> "${DIRECTORY}"/groups/dns_routes.sh
                    echo "ip netns exec \$PID ip route add "$(subnet_group "${group_number}")" via "${subnet_group%/*}" " >> "${DIRECTORY}"/groups/dns_routes.sh
                fi
            done
        fi
    done

    # connect measurement to dns service
    br_name="dns_measurement"
    subnet_bridge="$(subnet_router_DNS -1 "bridge")"
    subnet_dns="$(subnet_router_DNS -1 "dns")"
    subnet_measurement="$(subnet_router_DNS -1 "measurement")"

    echo -n "-- add-br "${br_name}" ">> "${DIRECTORY}"/groups/add_bridges.sh
    echo "ip link set dev ${br_name} up" >> "${DIRECTORY}"/groups/ip_setup.sh
    ./setup/ovs-docker.sh add-port "${br_name}" measurement DNS --ipaddress="${subnet_dns}"
    ./setup/ovs-docker.sh add-port "${br_name}" dns MEASUREMENT --ipaddress="${subnet_measurement}"
    echo "ip netns exec \$PID ip route add "${subnet_measurement%/*}" dev measurement " >> "${DIRECTORY}"/groups/dns_routes.sh
fi
