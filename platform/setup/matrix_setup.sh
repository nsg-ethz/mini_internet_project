#!/bin/bash
#
# start matrix container
# setup links between groups and matrix container

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"
source "${DIRECTORY}"/config/subnet_config.sh

# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt
group_numbers=${#groups[@]}

location="${DIRECTORY}"/groups/matrix/
mkdir $location

touch "$location"/destination_ips.txt
chmod +x "${location}"/destination_ips.txt


# start matrix container
docker run -itd --net='none' --name="MATRIX" --privileged --pids-limit 500 \
    -v "${location}"/destination_ips.txt:/home/destination_ips.txt thomahol/d_matrix

# no icmp rate limiting
docker exec -d MATRIX bash -c 'sysctl -w net.ipv4.icmp_ratelimit="0" > /dev/null' &

echo -n "-- add-br matrix " >> "${DIRECTORY}"/groups/add_bridges.sh
echo "ip a add 0.0.0.0 dev matrix" >> "${DIRECTORY}"/groups/ip_setup.sh

for ((k=0;k<group_numbers;k++)); do
    group_k=(${groups[$k]})
    group_number="${group_k[0]}"
    group_as="${group_k[1]}"
    group_config="${group_k[2]}"
    group_router_config="${group_k[3]}"
    group_internal_links="${group_k[4]}"

    if [ "${group_as}" != "IXP" ];then

        readarray routers < "${DIRECTORY}"/config/$group_router_config
        readarray intern_links < "${DIRECTORY}"/config/$group_internal_links
        n_routers=${#routers[@]}
        n_intern_links=${#intern_links[@]}

        # find the ID of that router
        for i in "${!routers[@]}"; do
           if [[ "${routers[$i]}" == *'MATRIX_TARGET'* ]]; then
               dest_router_id=$i;
           fi
        done
        subnet="$(subnet_host_router "${group_number}" "$dest_router_id" host)"
        echo $group_number" "${subnet%/*} >> ${location}/destination_ips.txt

        for ((i=0;i<n_routers;i++)); do
            router_i=(${routers[$i]})
            rname="${router_i[0]}"
            property1="${router_i[1]}"

            if [ "${property1}" = "MATRIX"  ];then
                subnet_bridge="$(subnet_router_MATRIX "${group_number}" "bridge")"
                    subnet_matrix="$(subnet_router_MATRIX "${group_number}" "matrix")"
                subnet_group="$(subnet_router_MATRIX "${group_number}" "group")"

                ./setup/ovs-docker.sh add-port matrix group_"${group_number}"  \
                MATRIX --ipaddress="${subnet_matrix}"

                mod=$((${group_number} % 100))
                div=$((${group_number} / 100))

                if [ $mod -lt 10 ];then
                    mod="0"$mod
                fi
                if [ $div -lt 10 ];then
                    div="0"$div
                fi

                ./setup/ovs-docker.sh add-port matrix matrix_"${group_number}" \
                "${group_number}"_"${rname}"router --ipaddress="${subnet_group}" \
                --macaddress="aa:11:11:11:"$div":"$mod

                ./setup/ovs-docker.sh connect-ports matrix \
                group_"${group_number}" MATRIX \
                matrix_"${group_number}" "${group_number}"_"${rname}"router
            fi
        done
    fi
done
