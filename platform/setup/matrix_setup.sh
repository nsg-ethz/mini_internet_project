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
echo '' > "$location"/ping_all_groups.sh
chmod +x "${location}"/ping_all_groups.sh

# start matrix container
docker run -itd --net='none' --name="MATRIX" --privileged --pids-limit 500 \
    -v "${location}"/ping_all_groups.sh:/home/ping_all_groups.sh thomahol/d_matrix

echo -n "-- add-br matrix " >> "${DIRECTORY}"/groups/add_bridges.sh
echo "ifconfig matrix 0.0.0.0 up" >> "${DIRECTORY}"/groups/ip_setup.sh

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
