#!/bin/bash
#
# start mgt container
# setup links between groups and mgt container

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"
source "${DIRECTORY}"/config/subnet_config.sh

# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt
readarray routers < "${DIRECTORY}"/config/router_config.txt

group_numbers=${#groups[@]}
n_routers=${#routers[@]}

# start mgt container
subnet_dns="$(subnet_router_DNS -1 "dns")"
docker run -itd --net='none' --dns="${subnet_dns%/*}" \
	--name="MGT" --privileged thomahol/d_mgt

passwd="$(openssl rand -hex 8)"
echo "${passwd}" >> "${DIRECTORY}"/groups/ssh_mgt.txt
echo -e ""${passwd}"\n"${passwd}"" | docker exec -i MGT passwd root

subnet_ssh_mgt="$(subnet_ext_sshContainer -1 "MGT")"
./setup/ovs-docker.sh add-port ssh_to_group ssh_in MGT --ipaddress="${subnet_ssh_mgt}"

echo -n "-- add-br mgt " >> "${DIRECTORY}"/groups/add_bridges.sh
echo "ifconfig mgt 0.0.0.0 up" >> "${DIRECTORY}"/groups/ip_setup.sh

for ((i=0;i<n_routers;i++)); do
    router_i=(${routers[$i]})
    rname="${router_i[0]}"
    property1="${router_i[1]}"

    if [ "${property1}" = "MGT"  ];then
        for ((k=0;k<group_numbers;k++)); do
            group_k=(${groups[$k]})
            group_number="${group_k[0]}"
            group_as="${group_k[1]}"

            if [ "${group_as}" != "IXP" ];then
                subnet_bridge="$(subnet_router_MGT "${group_number}" "bridge")"
                subnet_mgt="$(subnet_router_MGT "${group_number}" "mgt")"
                subnet_group="$(subnet_router_MGT "${group_number}" "group")"

                ./setup/ovs-docker.sh add-port mgt group_"${group_number}"  \
                MGT --ipaddress="${subnet_mgt}"

                ./setup/ovs-docker.sh add-port mgt mgt_"${group_number}" \
                "${group_number}"_"${rname}"router --ipaddress="${subnet_group}" \
                --macaddress="aa:22:22:22:22:"${group_number}

                ./setup/ovs-docker.sh connect-ports mgt \
                group_"${group_number}" MGT \
                mgt_"${group_number}" "${group_number}"_"${rname}"router
            fi
        done
    fi
done
