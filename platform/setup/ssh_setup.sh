#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"
source "${DIRECTORY}"/config/subnet_config.sh

# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt
readarray routers < "${DIRECTORY}"/config/router_config.txt
readarray intern_links < "${DIRECTORY}"/config/internal_links_config.txt
readarray extern_links < "${DIRECTORY}"/config/external_links_config.txt
readarray l2_switches < "${DIRECTORY}"/config/layer2_switches_config.txt
readarray l2_links < "${DIRECTORY}"/config/layer2_links_config.txt
readarray l2_hosts < "${DIRECTORY}"/config/layer2_hosts_config.txt

group_numbers=${#groups[@]}
n_routers=${#routers[@]}
n_intern_links=${#intern_links[@]}
n_extern_links=${#extern_links[@]}
n_l2_switches=${#l2_switches[@]}
n_l2_links=${#l2_links[@]}
n_l2_hosts=${#l2_hosts[@]}

# bridge for connection from host to ssh containers
echo -n "-- add-br ssh_to_group " >> "${DIRECTORY}"/groups/add_bridges.sh

subnet_bridge="$(subnet_ext_sshContainer -1 "bridge")"
echo "ifconfig ssh_to_group $subnet_bridge up" >> "${DIRECTORY}"/groups/ip_setup.sh

# General a pair of keys for the server, and put the public in the proxy container
ssh-keygen -t rsa -b 4096 -C "comment" -P "" -f "groups/id_rsa" -q
cp groups/id_rsa.pub groups/authorized_keys

docker cp "${DIRECTORY}"/groups/authorized_keys MGT:/root/.ssh/authorized_keys &


for ((k=0;k<group_numbers;k++)); do
    group_k=(${groups[$k]})
    group_number="${group_k[0]}"
    group_as="${group_k[1]}"

    if [ "${group_as}" != "IXP" ];then
        # genarate key pair for authentification between ssh container and group containers
        ssh-keygen -t rsa -b 4096 -C "comment" -P "" -f "groups/g"${group_number}"/id_rsa" -q

        # copy private key to container and change access rights
        docker cp "${DIRECTORY}"/groups/g"${group_number}"/id_rsa "${group_number}"_ssh:/root/.ssh/id_rsa
        docker cp "${DIRECTORY}"/groups/authorized_keys "${group_number}"_ssh:/root/.ssh/authorized_keys

        # generate password for login to ssh container, safe it to group folder
        passwd="$(openssl rand -hex 8)"
        echo "${group_number} ${passwd}" >> "${DIRECTORY}"/groups/ssh_passwords.txt
        echo -e ""${passwd}"\n"${passwd}"" | docker exec -i "${group_number}"_ssh passwd root
        echo -e ""${passwd}"\n"${passwd}"" | docker exec -i "${group_number}"_ssh service ssh restart &>/dev/nul
        sleep 1

        # bridge to connect ssh container and group containers
        subnet_ssh_to_group="$(subnet_ext_sshContainer "${group_number}" "sshContainer")"
        subnet_ssh_to_cont="$(subnet_sshContainer_groupContainer "${group_number}" -1 -1 "sshContainer")"

        echo -n "-- add-br "${group_number}"-ssh " >> "${DIRECTORY}"/groups/add_bridges.sh
        echo "ifconfig "${group_number}"-ssh 0.0.0.0 up" >> "${DIRECTORY}"/groups/ip_setup.sh

        # Connect the proxy container to the virtual devices
        ./setup/ovs-docker.sh add-port "${group_number}"-ssh ssh "${group_number}"_ssh --ipaddress="${subnet_ssh_to_cont}"
        # Connect the proxy container to the main host
        ./setup/ovs-docker.sh add-port ssh_to_group ssh_in "${group_number}"_ssh --ipaddress="${subnet_ssh_to_group}"

        for ((i=0;i<n_routers;i++)); do
            router_i=(${routers[$i]})
            rname="${router_i[0]}"
            property1="${router_i[1]}"
            property2="${router_i[2]}"

            #ssh login for router"
            subnet_router="$(subnet_sshContainer_groupContainer "${group_number}" "${i}" -1 "router")"
            ./setup/ovs-docker.sh add-port "${group_number}"-ssh ssh "${group_number}"_"${rname}"router --ipaddress="${subnet_router}"
            docker cp "${DIRECTORY}"/groups/g"${group_number}"/id_rsa.pub "${group_number}"_"${rname}"router:/root/.ssh/authorized_keys

            if [ "${property2}" == "host" ];then
                #ssh login for host
                subnet_host="$(subnet_sshContainer_groupContainer "${group_number}" "${i}" -1 "host")"
                ./setup/ovs-docker.sh add-port "${group_number}"-ssh ssh "${group_number}"_"${rname}"host --ipaddress="${subnet_host}"
                docker cp "${DIRECTORY}"/groups/g"${group_number}"/id_rsa.pub "${group_number}"_"${rname}"host:/root/.ssh/authorized_keys

            elif [ "${property2}" == "L2" ];then
                for ((l=0;l<n_l2_switches;l++)); do
                    switch_l=(${l2_switches[$l]})
                    sname="${switch_l[0]}"
                    connected="${switch_l[1]}"
                    cont_name="${group_number}""_""${rname}""_L2_""${sname}"
                    subnet_l2_switch="$(subnet_sshContainer_groupContainer "${group_number}" "${i}" "$((${l}+2))" "L2")"
                    ./setup/ovs-docker.sh add-port "${group_number}"-ssh ssh "${cont_name}" --ipaddress="${subnet_l2_switch}"
                    docker cp "${DIRECTORY}"/groups/g"${group_number}"/id_rsa.pub "${cont_name}":/root/.ssh/authorized_keys
                done

                for ((l=0;l<n_l2_hosts;l++)); do
                    host_l=(${l2_hosts[$l]})
                    hname="${host_l[0]}"
                    sname="${host_l[1]}"
                    cont_name="${group_number}""_""${rname}""_L2_""${hname}"
                    subnet_l2_host="$(subnet_sshContainer_groupContainer "${group_number}" "${i}" "$((${l}+${n_l2_switches}+2))" "L2")"

                    if [[ $hname != vpn* ]]; then
                        ./setup/ovs-docker.sh add-port "${group_number}"-ssh ssh "${cont_name}" --ipaddress="${subnet_l2_host}"
                        docker cp "${DIRECTORY}"/groups/g"${group_number}"/id_rsa.pub "${cont_name}":/root/.ssh/authorized_keys
                    fi
                done
            fi
        done
    fi
done
