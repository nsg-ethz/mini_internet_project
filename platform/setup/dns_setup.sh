#!/bin/bash
#
# start dns server container
# setup links between groups and dns server
# connect measurement container to dns server

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"
source "${DIRECTORY}"/config/subnet_config.sh

# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt
group_numbers=${#groups[@]}

echo "#!/bin/bash" > "${DIRECTORY}"/groups/dns_routes.sh
chmod +x "${DIRECTORY}"/groups/dns_routes.sh

# dns
docker run -itd --net='none'  --name="DNS" --privileged thomahol/d_dns

echo -n "-- add-br dns " >> "${DIRECTORY}"/groups/add_bridges.sh
echo "ip link set dev dns up" >> "${DIRECTORY}"/groups/ip_setup.sh

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

                echo "docker exec -d DNS ip route add "${subnet_group%/*}" dev group_"${group_number}" " >> "${DIRECTORY}"/groups/dns_routes.sh
                echo "docker exec -d DNS ip route add "$(subnet_group "${group_number}")" via "${subnet_group%/*}" " >> "${DIRECTORY}"/groups/dns_routes.sh
            fi
        done
    fi
done

# copy dns config files to container generated from dns_config.sh
docker cp "${DIRECTORY}"/groups/dns/group_config DNS:/etc/bind/group_config
docker cp "${DIRECTORY}"/groups/dns/zones DNS:/etc/bind/zones
docker cp "${DIRECTORY}"/groups/dns/named.conf.local DNS:/etc/bind/named.conf.local
docker cp "${DIRECTORY}"/groups/dns/named.conf.options DNS:/etc/bind/named.conf.options

# connect measurement to dns service
br_name="dns_measurement"
subnet_bridge="$(subnet_router_DNS -1 "bridge")"
subnet_dns="$(subnet_router_DNS -1 "dns")"
subnet_measurement="$(subnet_router_DNS -1 "measurement")"

echo -n "-- add-br "${br_name}" ">> "${DIRECTORY}"/groups/add_bridges.sh
echo "ip link set dev ${br_name} up" >> "${DIRECTORY}"/groups/ip_setup.sh
./setup/ovs-docker.sh add-port "${br_name}" measurement DNS --ipaddress="${subnet_dns}"
./setup/ovs-docker.sh add-port "${br_name}" dns MEASUREMENT --ipaddress="${subnet_measurement}"
echo "docker exec -d DNS ip route add "${subnet_measurement%/*}" dev measurement " >> "${DIRECTORY}"/groups/dns_routes.sh
