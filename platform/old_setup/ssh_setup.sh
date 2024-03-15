#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"
source "${DIRECTORY}"/config/subnet_config.sh
source "${DIRECTORY}"/setup/_parallel_helper.sh

# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt
group_numbers=${#groups[@]}

# bridge for connection from host to ssh containers
echo -n "-- add-br ssh_to_group " >> "${DIRECTORY}"/groups/add_bridges.sh

subnet_bridge="$(subnet_ext_sshContainer -1 "bridge")"
echo "ip a add $subnet_bridge dev ssh_to_group" >> "${DIRECTORY}"/groups/ip_setup.sh
echo "ip link set dev ssh_to_group up" >> "${DIRECTORY}"/groups/ip_setup.sh

# Generate a pair of keys for the server, and put the public in the proxy container
ssh-keygen -t rsa -b 4096 -C "ta key" -P "" -f "groups/id_rsa" -q
cp groups/id_rsa.pub groups/authorized_keys

if [ -n "$(docker ps | grep "MEASUREMENT")" ]; then
    docker cp "${DIRECTORY}"/groups/authorized_keys MEASUREMENT:/root/.ssh/authorized_keys > /dev/null
fi

for ((k = 0; k < group_numbers; k++)); do
    group_k=(${groups[$k]})
    group_number="${group_k[0]}"
    group_as="${group_k[1]}"
    group_config="${group_k[2]}"
    group_router_config="${group_k[3]}"
    group_internal_links="${group_k[4]}"
    group_layer2_switches="${group_k[5]}"
    group_layer2_hosts="${group_k[6]}"
    group_layer2_links="${group_k[7]}"

    if [ "${group_as}" != "IXP" ]; then

        readarray routers < "${DIRECTORY}"/config/$group_router_config
        readarray intern_links < "${DIRECTORY}"/config/$group_internal_links
        readarray l2_switches < "${DIRECTORY}"/config/$group_layer2_switches
        readarray l2_hosts < "${DIRECTORY}"/config/$group_layer2_hosts
        readarray l2_links < "${DIRECTORY}"/config/$group_layer2_links
        n_routers=${#routers[@]}
        n_intern_links=${#intern_links[@]}
        n_l2_switches=${#l2_switches[@]}
        n_l2_hosts=${#l2_hosts[@]}
        n_l2_links=${#l2_links[@]}

        # genarate key pair for authentification between ssh container and group containers
        ssh-keygen -t rsa -b 4096 -C "internal key group ${group_number}" -P "" -f "groups/g"${group_number}"/id_rsa" -q
        echo 'command="vtysh \"${SSH_ORIGINAL_COMMAND}\"" '$(cat "${DIRECTORY}"/groups/g"${group_number}"/id_rsa.pub) > "${DIRECTORY}"/groups/g"${group_number}"/id_rsa_command.pub

        # copy private key to container and change access rights
        docker cp "${DIRECTORY}"/groups/g"${group_number}"/id_rsa "${group_number}"_ssh:/root/.ssh/id_rsa > /dev/null
        docker cp "${DIRECTORY}"/groups/g"${group_number}"/id_rsa.pub "${group_number}"_ssh:/root/.ssh/id_rsa.pub > /dev/null
        docker cp "${DIRECTORY}"/groups/authorized_keys "${group_number}"_ssh:/root/.ssh/authorized_keys > /dev/null
        docker cp "${DIRECTORY}"/groups/authorized_keys "${group_number}"_ssh:/etc/ssh/authorized_keys > /dev/null

        # generate password for login to ssh container, save it to group folder
        passwd=$(awk "\$1 == \"${group_number}\" { print \$2 }" "${DIRECTORY}/groups/passwords.txt")
        echo -e ""${passwd}"\n"${passwd}"" | docker exec -i "${group_number}"_ssh passwd root
        docker exec "${group_number}"_ssh bash -c "kill -HUP \$(cat /var/run/sshd.pid)"

        # bridge to connect ssh container and group containers
        subnet_ssh_to_group="$(subnet_ext_sshContainer "${group_number}" "sshContainer")"
        subnet_ssh_to_cont="$(subnet_sshContainer_groupContainer "${group_number}" -1 -1 "sshContainer")"

        echo -n "-- add-br "${group_number}"-ssh " >> "${DIRECTORY}"/groups/add_bridges.sh
        echo "ip link set dev ${group_number}-ssh up" >> "${DIRECTORY}"/groups/ip_setup.sh

        # Connect the proxy container to the virtual devices
        ./setup/ovs-docker.sh add-port "${group_number}"-ssh ssh "${group_number}"_ssh --ipaddress="${subnet_ssh_to_cont}"
        # Connect the proxy container to the main host
        ./setup/ovs-docker.sh add-port ssh_to_group ssh_in "${group_number}"_ssh --ipaddress="${subnet_ssh_to_group}"

        l2_done=''
        for ((i = 0; i < n_routers; i++)); do
            router_i=(${routers[$i]})
            rname="${router_i[0]}"
            property1="${router_i[1]}"
            property2="${router_i[2]}"
            rcmd="${router_i[3]}"
            dname=$(echo $property2 | cut -s -d ':' -f 2)
            l2_switch_cur=0
            l2_host_cur=0

            # #ssh login for router"
            # subnet_router="$(subnet_sshContainer_groupContainer "${group_number}" "${i}" -1 "router")"
            # ./setup/ovs-docker.sh add-port "${group_number}"-ssh ssh "${group_number}"_"${rname}"router --ipaddress="${subnet_router}"

            # if [ "${rcmd}" == "vtysh" ]; then
            #     docker cp "${DIRECTORY}"/groups/g"${group_number}"/id_rsa_command.pub "${group_number}"_"${rname}"router:/root/.ssh/authorized_keys > /dev/null
            # else
            #     docker cp "${DIRECTORY}"/groups/g"${group_number}"/id_rsa.pub "${group_number}"_"${rname}"router:/root/.ssh/authorized_keys > /dev/null
            # fi
            extra=""
            all_in_one="false"
            if [[ ${#router_i[@]} -gt 4 ]]; then
                if [[ "${router_i[4]}" == "ALL" ]]; then
                    extra="${i}"
                    all_in_one="true"
                fi
            fi

            if [[ "$all_in_one" == "false" || $i -eq 0 ]]; then
                #ssh login for router"
                subnet_router="$(subnet_sshContainer_groupContainer "${group_number}" "${i}" -1 "router")"
                ./setup/ovs-docker.sh add-port "${group_number}"-ssh ssh "${group_number}"_"${rname}"router --ipaddress="${subnet_router}"

                if [ "${rcmd}" == "vtysh" ]; then
                    docker cp "${DIRECTORY}"/groups/g"${group_number}"/id_rsa_command.pub "${group_number}"_"${rname}"router:/root/.ssh/authorized_keys > /dev/null
                else
                    docker cp "${DIRECTORY}"/groups/g"${group_number}"/id_rsa.pub "${group_number}"_"${rname}"router:/root/.ssh/authorized_keys > /dev/null
                fi
            fi

            if [[ ! -z "${dname}" ]]; then
                #ssh login for host
                subnet_host="$(subnet_sshContainer_groupContainer "${group_number}" "${i}" -1 "host")"
                # ./setup/ovs-docker.sh add-port "${group_number}"-ssh ssh "${group_number}"_"${rname}"host --ipaddress="${subnet_host}"
                # docker cp "${DIRECTORY}"/groups/g"${group_number}"/id_rsa.pub "${group_number}"_"${rname}"host:/root/.ssh/authorized_keys > /dev/null
                # docker exec "${group_number}"_"${rname}"host bash -c "kill -HUP \$(cat /var/run/sshd.pid)"
                ./setup/ovs-docker.sh add-port "${group_number}"-ssh ssh "${group_number}"_"${rname}"host"${extra}" --ipaddress="${subnet_host}"
                docker cp "${DIRECTORY}"/groups/g"${group_number}"/id_rsa.pub "${group_number}"_"${rname}"host"${extra}":/root/.ssh/authorized_keys > /dev/null
                docker exec "${group_number}"_"${rname}"host"${extra}" bash -c "kill -HUP \$(cat /var/run/sshd.pid)"
            fi

            if [[ "${property2}" == *L2* ]]; then
                l2_name=$(echo $property2 | cut -s -d ':' -f 1 | cut -f 2 -d '-')

                if [[ ! $l2_done =~ (^| )$l2_name($| ) ]]; then
                    for ((l = 0; l < n_l2_switches; l++)); do
                        switch_l=(${l2_switches[$l]})
                        l2_name_tmp="${switch_l[0]}"
                        sname="${switch_l[1]}"
                        connected="${switch_l[2]}"
                        cont_name=${group_number}_L2_${l2_name_tmp}_${sname}

                        if [ $l2_name_tmp == $l2_name ]; then
                            subnet_l2_switch="$(subnet_sshContainer_groupContainer "${group_number}" "${i}" "${l2_switch_cur}" "L2")"
                            ./setup/ovs-docker.sh add-port "${group_number}"-ssh ssh "${cont_name}" --ipaddress="${subnet_l2_switch}"
                            docker cp "${DIRECTORY}"/groups/g"${group_number}"/id_rsa.pub "${cont_name}":/root/.ssh/authorized_keys > /dev/null
                            l2_switch_cur=$((${l2_switch_cur} + 1))
                        fi
                    done

                    for ((l = 0; l < n_l2_hosts; l++)); do
                        host_l=(${l2_hosts[$l]})
                        hname="${host_l[0]}"
                        l2_name_tmp="${host_l[2]}"
                        sname="${host_l[3]}"
                        cont_name=${group_number}_L2_${l2_name_tmp}_${hname}

                        if [ $l2_name_tmp == $l2_name ]; then
                            subnet_l2_host="$(subnet_sshContainer_groupContainer "${group_number}" "${i}" "$((${l2_host_cur} + ${l2_switch_cur}))" "L2")"

                            if [[ $hname != vpn* ]]; then
                                ./setup/ovs-docker.sh add-port "${group_number}"-ssh ssh "${cont_name}" --ipaddress="${subnet_l2_host}"
                                docker cp "${DIRECTORY}"/groups/g"${group_number}"/id_rsa.pub "${cont_name}":/root/.ssh/authorized_keys > /dev/null
                                l2_host_cur=$((${l2_host_cur} + 1))
                            fi

                        fi
                    done

                    l2_done=${l2_done}' '$l2_name
                fi

            fi
        done
    fi
done

wait
