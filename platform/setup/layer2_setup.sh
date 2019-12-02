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

# Needed to create the VLAN on the router interface
modprobe 8021q

# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt
readarray routers < "${DIRECTORY}"/config/router_config.txt
readarray l2_switches < "${DIRECTORY}"/config/layer2_switches_config.txt
readarray l2_links < "${DIRECTORY}"/config/layer2_links_config.txt
readarray l2_hosts < "${DIRECTORY}"/config/layer2_hosts_config.txt

group_numbers=${#groups[@]}
n_routers=${#routers[@]}
n_l2_switches=${#l2_switches[@]}
n_l2_links=${#l2_links[@]}
n_l2_hosts=${#l2_hosts[@]}


# Layer2 connectivity
for ((k=0;k<group_numbers;k++)); do
    group_k=(${groups[$k]})
    group_number="${group_k[0]}"
    group_as="${group_k[1]}"
    if [ "${group_as}" != "IXP" ];then
        for ((i=0;i<n_routers;i++)); do
            router_i=(${routers[$i]})
            rname="${router_i[0]}"
            property1="${router_i[1]}"
            property2="${router_i[2]}"
            if [ "${property2}" == "L2" ];then

                br_name="l2-""${group_number}""-""${rname}"
                echo -n "-- add-br "${br_name}" " >> "${DIRECTORY}"/groups/add_bridges.sh

                for ((l=0;l<n_l2_switches;l++)); do
                    switch_l=(${l2_switches[$l]})
                    sname="${switch_l[0]}"
                    connected="${switch_l[1]}"
                    sys_id="${switch_l[2]}"


                    docker exec -d "${group_number}""_""${rname}""_L2_""${sname}" \
                        ovs-vsctl add-br br0

                    docker exec -d "${group_number}""_""${rname}""_L2_""${sname}" \
                        ovs-vsctl set bridge br0 stp_enable=true

                    docker exec -d "${group_number}""_""${rname}""_L2_""${sname}" \
                        ovs-vsctl set-fail-mode br0 standalone

                    docker exec -d "${group_number}""_""${rname}""_L2_""${sname}" \
                        ovs-vsctl set bridge br0 other_config:stp-system-id="${sys_id}"

                    docker exec -d "${group_number}""_""${rname}""_L2_""${sname}" \
                        ovs-vsctl set bridge br0 other_config:stp-priority=$((100*l+1))

                    if [ "${connected}" == "router" ];then
                        subnet_student="$(subnet_l2_router "${group_number}" "${i}" "student")"
                        subnet_staff="$(subnet_l2_router "${group_number}" "${i}" "staff")"

                        ./setup/ovs-docker.sh add-port "${br_name}" "${rname}""-L2" \
                          "${group_number}""_""${rname}""router"
                        ./setup/ovs-docker.sh add-port "${br_name}" "${rname}""router" \
                          "${group_number}""_""${rname}""_L2_""${sname}"

                        ./setup/ovs-docker.sh connect-ports "${br_name}" \
                        "${rname}""-L2" "${group_number}""_""${rname}""router" \
                        "${rname}""router" "${group_number}""_""${rname}""_L2_""${sname}"

                        echo "docker exec -d "${group_number}""_""${rname}""_L2_""${sname}" ovs-vsctl add-port br0 "${rname}""router"" >> "${DIRECTORY}"/groups/l2_init_switch.sh

                    fi
                done

                for ((l=0;l<n_l2_links;l++)); do
                    row_l=(${l2_links[$l]})
                    switch1="${row_l[0]}"
                    switch2="${row_l[1]}"
                    throughput="${row_l[2]}"
                    delay="${row_l[3]}"

                    ./setup/ovs-docker.sh add-port "${br_name}" "${rname}"-"${switch2}" \
                    "${group_number}""_""${rname}""_L2_""${switch1}" \
                    --delay="${delay}" --throughput="${throughput}"

                    ./setup/ovs-docker.sh add-port "${br_name}" "${rname}"-"${switch1}" \
                    "${group_number}""_""${rname}""_L2_""${switch2}" \
                    --delay="${delay}" --throughput="${throughput}"

                    ./setup/ovs-docker.sh connect-ports "${br_name}" \
                    "${rname}"-"${switch2}" "${group_number}""_""${rname}""_L2_""${switch1}" \
                    "${rname}"-"${switch1}" "${group_number}""_""${rname}""_L2_""${switch2}"

                    echo "docker exec -d "${group_number}""_""${rname}""_L2_""${switch1}" ovs-vsctl add-port br0 "${rname}"-"${switch2}"" >> "${DIRECTORY}"/groups/l2_init_switch.sh
                    echo "docker exec -d "${group_number}""_""${rname}""_L2_""${switch2}" ovs-vsctl add-port br0 "${rname}"-"${switch1}"" >> "${DIRECTORY}"/groups/l2_init_switch.sh

                    echo "ovs-vsctl set bridge "${br_name}" other-config:forward-bpdu=true" >> "${DIRECTORY}"/groups/l2_init_switch.sh

                    echo "docker exec -d "${group_number}""_""${rname}""_L2_""${switch1}" ovs-vsctl set Port "${rname}"-"${switch2}" trunks=0 " >> "${DIRECTORY}"/groups/l2_init_switch.sh
                    echo "docker exec -d "${group_number}""_""${rname}""_L2_""${switch2}" ovs-vsctl set Port "${rname}"-"${switch1}" trunks=0 " >> "${DIRECTORY}"/groups/l2_init_switch.sh
                done

                for ((l=0;l<n_l2_hosts;l++)); do
                    host_l=(${l2_hosts[$l]})
                    hname="${host_l[0]}"
                    sname="${host_l[1]}"
                    throughput="${host_l[2]}"
                    delay="${host_l[3]}"

                    if [[ $hname == vpn* ]]; then
                        echo "ip link add ${rname}-$hname type veth peer name g${group_number}_$hname" >> "${DIRECTORY}"/groups/add_vpns.sh
                        echo "PID=$(sudo docker inspect -f '{{.State.Pid}}' "${group_number}""_""${rname}""_L2_""${sname}")" >> "${DIRECTORY}"/groups/add_vpns.sh
                        echo "ip link set ${rname}-$hname netns \$PID" >> "${DIRECTORY}"/groups/add_vpns.sh
                        echo "docker exec -d "${group_number}""_""${rname}""_L2_""${sname}" ifconfig ${rname}-$hname 0.0.0.0 up" >> "${DIRECTORY}"/groups/add_vpns.sh
                        echo "docker exec -d "${group_number}""_""${rname}""_L2_""${sname}" ovs-vsctl add-port br0 ${rname}-$hname" >> "${DIRECTORY}"/groups/add_vpns.sh

                        echo "ifconfig g${group_number}_$hname 0.0.0.0 up" >> groups/add_vpns.sh
                        echo "ifconfig tap_g"${group_number}_$hname" 0.0.0.0 up" >> groups/add_vpns.sh

                        echo "sudo ovs-vsctl add-port vpnbr_${group_k}_${host_l} tap_g"${group_number}_$hname >> groups/add_vpns.sh
                        echo "sudo ovs-vsctl add-port vpnbr_${group_k}_${host_l} g${group_number}_$hname" >> groups/add_vpns.sh
                        # echo "port_id1=\`ovs-vsctl get Interface tap_g"${group_number}_$hname" ofport\`" >> groups/add_vpns.sh
                        # echo "port_id2=\`ovs-vsctl get Interface g${group_number}_$hname ofport\`" >> groups/add_vpns.sh
                        # echo "ovs-ofctl add-flow vpnbr_${group_k}_${host_l} in_port=\$port_id1,actions=output:\$port_id2" >> groups/add_vpns.sh
                        # echo "ovs-ofctl add-flow vpnbr_${group_k}_${host_l} in_port=\$port_id2,actions=output:\$port_id1" >> groups/add_vpns.sh

                        echo "echo -n \" -- set interface tap_g"${group_number}_$hname" ingress_policing_rate="${throughput}" \" >> groups/throughput.sh " >>  "${DIRECTORY}"/groups/delay_throughput.sh
                        echo "tc qdisc add dev tap_g${group_number}_$hname root netem delay ${delay} " >>  "${DIRECTORY}"/groups/delay_throughput.sh

                    else
                        ./setup/ovs-docker.sh add-port "${br_name}" "${rname}"-"${hname}" \
                        "${group_number}""_""${rname}""_L2_""${sname}" \
                        --delay="${delay}" --throughput="${throughput}"

                        ./setup/ovs-docker.sh add-port "${br_name}" "${rname}"-"${sname}" \
                        "${group_number}""_""${rname}""_L2_""${hname}" \
                        --delay="${delay}" --throughput="${throughput}"

                        ./setup/ovs-docker.sh connect-ports "${br_name}" \
                        "${rname}"-"${hname}" "${group_number}""_""${rname}""_L2_""${sname}" \
                        "${rname}"-"${sname}" "${group_number}""_""${rname}""_L2_""${hname}"

                        echo "docker exec -d "${group_number}""_""${rname}""_L2_""${sname}" ovs-vsctl add-port br0 "${rname}"-"${hname}"" >> "${DIRECTORY}"/groups/l2_init_switch.sh
                        echo "ovs-vsctl set bridge "${br_name}" other-config:forward-bpdu=true" >> "${DIRECTORY}"/groups/l2_init_switch.sh
                    fi
                done
            fi
        done
    fi
done
