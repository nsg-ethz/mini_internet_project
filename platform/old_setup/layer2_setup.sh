#!/bin/bash
#
# create links between hosts and switches
# what switch a host is connected is defined in config/layer2_hosts_config.txt
# links between switches are defined in config/layer2_links_config.txt
# ip subnets are defined in ./config/subnet_config.sh

set -o errexit
set -o pipefail
set -o nounset


DIRECTORY="$1"
source "${DIRECTORY}"/config/subnet_config.sh
source "${DIRECTORY}"/setup/ovs-docker.sh

# Needed to create the VLAN on the router interface
modprobe 8021q

# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt
group_numbers=${#groups[@]}



# Layer2 connectivity
for ((k=0;k<group_numbers;k++)); do
    group_k=(${groups[$k]})
    group_number="${group_k[0]}"
    group_as="${group_k[1]}"
    group_router_config="${group_k[3]}"
    group_internal_links="${group_k[4]}"
    group_layer2_switches="${group_k[5]}"
    group_layer2_hosts="${group_k[6]}"
    group_layer2_links="${group_k[7]}"

    if [ "${group_as}" != "IXP" ];then

        readarray routers < "${DIRECTORY}"/config/$group_router_config
        readarray l2_switches < "${DIRECTORY}"/config/$group_layer2_switches
        readarray l2_hosts < "${DIRECTORY}"/config/$group_layer2_hosts
        readarray l2_links < "${DIRECTORY}"/config/$group_layer2_links
        n_routers=${#routers[@]}
        n_l2_switches=${#l2_switches[@]}
        n_l2_hosts=${#l2_hosts[@]}
        n_l2_links=${#l2_links[@]}

        if [ "${n_l2_switches}" = "0" -a "${n_l2_hosts}" = "0" -a "${n_l2_links}" = "0" ]; then
            # No L2 config, skip
            continue
        fi

        br_name="l2-"${group_number}
        echo -n "-- add-br "${br_name}" -- set-fail-mode "${br_name}" secure " >> "${DIRECTORY}"/groups/add_bridges.sh
        echo "ovs-vsctl set bridge "${br_name}" other-config:forward-bpdu=true" >> "${DIRECTORY}"/groups/l2_init_switch.sh

        for ((l=0;l<n_l2_switches;l++)); do
            switch_l=(${l2_switches[$l]})
            l2name="${switch_l[0]}"
            sname="${switch_l[1]}"
            connected="${switch_l[2]}"
            sys_id="${switch_l[3]}"
            stp_prio="${switch_l[4]}"

            docker exec -d "${group_number}""_L2_""${l2name}"_${sname} ovs-vsctl \
                -- add-br br0 \
                -- set bridge br0 stp_enable=true \
                -- set-fail-mode br0 standalone \
                -- set bridge br0 other_config:stp-system-id=${sys_id} \
                -- set bridge br0 other_config:stp-priority=$stp_prio
        done

        for ((l=0;l<n_l2_links;l++)); do
            row_l=(${l2_links[$l]})
            l2name1="${row_l[0]}"
            switch1="${row_l[1]}"
            l2name2="${row_l[2]}"
            switch2="${row_l[3]}"
            throughput="${row_l[4]}"
            delay="${row_l[5]}"

            ./setup/ovs-docker.sh add-port "${br_name}" "${group_number}"-"${switch2}" \
            "${group_number}""_L2_""${l2name1}"_${switch1} \
            --delay="${delay}" --throughput="${throughput}"

            ./setup/ovs-docker.sh add-port "${br_name}" "${group_number}"-"${switch1}" \
            "${group_number}""_L2_""${l2name2}"_${switch2} \
            --delay="${delay}" --throughput="${throughput}"

            ./setup/ovs-docker.sh connect-ports "${br_name}" \
            "${group_number}"-"${switch2}" "${group_number}""_L2_""${l2name1}"_${switch1} \
            "${group_number}"-"${switch1}" "${group_number}""_L2_""${l2name2}"_${switch2}

            # the configuration can only be done after the interface is up!
            echo "docker exec -d "${group_number}""_L2_""${l2name1}_${switch1}" ovs-vsctl" \
                 "add-port br0 "${group_number}"-"${switch2}"" \
                 "-- set Port "${group_number}"-"${switch2}" trunks=0" >> "${DIRECTORY}"/groups/l2_init_switch.sh
            echo "docker exec -d "${group_number}""_L2_""${l2name2}_${switch2}" ovs-vsctl" \
                 "add-port br0 "${group_number}"-"${switch1}"" \
                 "-- set Port "${group_number}"-"${switch1}" trunks=0" >> "${DIRECTORY}"/groups/l2_init_switch.sh

        done

        for ((l=0;l<n_l2_hosts;l++)); do
            host_l=(${l2_hosts[$l]})
            hname="${host_l[0]}"
            dname="${host_l[1]}"
            l2name="${host_l[2]}"
            sname="${host_l[3]}"
            throughput="${host_l[4]}"
            delay="${host_l[5]}"

            if [[ $hname == vpn* ]]; then
                echo "ip link add ${group_number}-$hname type veth peer name g${group_number}_$hname" >> "${DIRECTORY}"/groups/add_vpns.sh
                get_docker_pid "${group_number}_L2_${l2name}_${sname}"
                echo "PID=$DOCKER_PID" >> "${DIRECTORY}"/groups/add_vpns.sh
                echo "create_netns_link" >> "${DIRECTORY}"/groups/add_vpns.sh
                echo "ip link set ${group_number}-$hname netns \$PID" >> "${DIRECTORY}"/groups/add_vpns.sh
                echo "ip netns exec \$PID ip link set dev ${group_number}-$hname up" >> "${DIRECTORY}"/groups/add_vpns.sh
                echo "docker exec -d "${group_number}""_L2_""${l2name}_${sname}" ovs-vsctl add-port br0 ${group_number}-$hname" >> "${DIRECTORY}"/groups/add_vpns.sh
                echo "ip link set dev g${group_number}_$hname up" >> groups/add_vpns.sh
                echo "ip link set dev tap_g${group_number}_$hname up" >> groups/add_vpns.sh

                echo "ovs-vsctl add-port vpnbr_${group_k}_${host_l} tap_g"${group_number}_$hname >> groups/add_vpns.sh
                echo "ovs-vsctl add-port vpnbr_${group_k}_${host_l} g${group_number}_$hname" >> groups/add_vpns.sh

                echo "echo -n \" -- set interface tap_g"${group_number}_$hname" ingress_policing_rate="${throughput}" \" >> groups/throughput.sh " >>  "${DIRECTORY}"/groups/delay_throughput.sh
                echo "tc qdisc add dev tap_g${group_number}_$hname root netem delay ${delay} " >>  "${DIRECTORY}"/groups/delay_throughput.sh

            else
                ./setup/ovs-docker.sh add-port "${br_name}" "${group_number}"-"${hname}" \
                ${group_number}_L2_${l2name}_${sname} \
                --delay="${delay}" --throughput="${throughput}"

                ./setup/ovs-docker.sh add-port "${br_name}" "${group_number}"-"${sname}" \
                ${group_number}_L2_${l2name}_${hname} \
                --delay="${delay}" --throughput="${throughput}"

                ./setup/ovs-docker.sh connect-ports ${br_name} \
                ${group_number}-${hname} ${group_number}_L2_${l2name}_${sname} \
                ${group_number}-${sname} ${group_number}_L2_${l2name}_${hname}

                echo "docker exec -d "${group_number}""_L2_""${l2name}_${sname}" ovs-vsctl add-port br0 "${group_number}"-"${hname}"" >> "${DIRECTORY}"/groups/l2_init_switch.sh
            fi
        done

        for ((i=0;i<n_routers;i++)); do
            router_i=(${routers[$i]})
            rname="${router_i[0]}"
            property1="${router_i[1]}"
            property2="${router_i[2]}"

                if [[ "${property2}" == L2* ]];then
                    for ((l=0;l<n_l2_switches;l++)); do
                        switch_l=(${l2_switches[$l]})
                        l2name="${switch_l[0]}"
                        sname="${switch_l[1]}"
                        connected="${switch_l[2]}"
                        sys_id="${switch_l[3]}"

                        if [ "${connected}" == "$rname" ];then
                            ./setup/ovs-docker.sh add-port "${br_name}" "${rname}""-L2" \
                              "${group_number}""_""${rname}""router" --throughput=10000
                            ./setup/ovs-docker.sh add-port "${br_name}" "${rname}""router" \
                              "${group_number}""_L2_""${l2name}_${sname}" --throughput=10000
                           
                            ./setup/ovs-docker.sh connect-ports "${br_name}" \
                            "${rname}""-L2" "${group_number}""_""${rname}""router" \
                            "${rname}""router" "${group_number}""_L2_""${l2name}_${sname}" \

                            echo "docker exec -d "${group_number}""_L2_""${l2name}_${sname}" ovs-vsctl add-port br0 "${rname}""router"" >> "${DIRECTORY}"/groups/l2_init_switch.sh
                        fi
                    done
            fi
        done
    fi
done
