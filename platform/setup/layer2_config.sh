#!/bin/bash

# set -x
set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"
source "${DIRECTORY}"/config/subnet_config.sh
source "${DIRECTORY}"/setup/ovs-docker.sh
source "${DIRECTORY}"/setup/_parallel_helper.sh

# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt
group_numbers=${#groups[@]}

# Layer2 connectivity
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
        readarray l2_switches < "${DIRECTORY}"/config/$group_layer2_switches
        readarray l2_hosts < "${DIRECTORY}"/config/$group_layer2_hosts
        readarray l2_links < "${DIRECTORY}"/config/$group_layer2_links
        n_routers=${#routers[@]}
        n_l2_switches=${#l2_switches[@]}
        n_l2_hosts=${#l2_hosts[@]}
        n_l2_links=${#l2_links[@]}

        declare -A l2_id
        declare -A l2_routerid

        # Initialization of the associative arrays
        for ((i = 0; i < n_routers; i++)); do
            router_i=(${routers[$i]})
            property2="$(echo ${router_i[2]} | cut -d ':' -f 1)"
            l2_id[$property2]=0
            l2_routerid[$property2]=1
        done

        idtmp=1
        for ((i = 0; i < n_routers; i++)); do
            router_i=(${routers[$i]})
            rname="${router_i[0]}"
            property1="${router_i[1]}"
            property2="$(echo ${router_i[2]} | cut -d ':' -f 1)"
            if [[ "${property2}" == *L2* ]]; then

                declare -A vlanset
                declare -A vlanl2set
                for ((l = 0; l < n_l2_hosts; l++)); do
                    host_l=(${l2_hosts[$l]})
                    vlan="${host_l[7]}"
                    vlanset[$vlan]=0
                    vlanl2set[${property2} - ${vlan}]=0
                done

                if [[ ${l2_id[$property2]} -eq 0 ]]; then
                    l2_id[$property2]=$idtmp
                    idtmp=$(($idtmp + 1))
                fi

                # Setup the 6in4 tunnels between the routers connected to the L2 networks
                subnet_local_router=$(subnet_router $group_number $i)

                for ((u = 0; u < group_numbers; u++)); do
                    group_tunnel=(${groups[$u]})
                    group_number_tunnel="${group_tunnel[0]}"
                    group_as_tunnel="${group_tunnel[1]}"

                    if [ "${group_as_tunnel}" != "IXP" ] && [ "${group_number_tunnel}" != "${group_number}" ]; then
                        subnet_remote_router=$(subnet_router $group_number_tunnel $i)

                        echo "docker exec -d ${group_number}_${rname}router ip tunnel add tun6to4_${group_number_tunnel} mode sit remote ${subnet_remote_router%/*} local ${subnet_local_router%/*} ttl 255" >> "${DIRECTORY}"/groups/g"${group_number}"/6in4_setup.sh

                        echo "docker exec -d ${group_number}_${rname}router ip link set tun6to4_${group_number_tunnel} up" >> "${DIRECTORY}"/groups/g"${group_number}"/6in4_setup.sh

                        for vlan in "${!vlanset[@]}"; do
                            subnet_remote_router_l2=$(subnet_l2_ipv6 $group_number_tunnel $((${l2_id[$property2]} - 1)) $vlan 0)

                            echo "docker exec -d ${group_number}_${rname}router ip route add ${subnet_remote_router_l2} dev tun6to4_${group_number_tunnel}" >> "${DIRECTORY}"/groups/g"${group_number}"/6in4_setup.sh
                        done
                    fi
                done
                # Done setting up the 6in4 tunnels
                for vlan in "${!vlanset[@]}"; do
                    get_docker_pid ${group_number}_${rname}router
                    PID=$DOCKER_PID
                    create_netns_link

                    subnet_router="$(subnet_l2 ${group_number} $((${l2_id[$property2]} - 1)) ${vlan} ${l2_routerid[$property2]})"
                    subnet_router_ipv6="$(subnet_l2_ipv6 ${group_number} $((${l2_id[$property2]} - 1)) ${vlan} ${l2_routerid[$property2]})"

                    if [ "$vlan" != "0" ]; then # VLAN 0 means there is no VLAN
                        ip netns exec $PID \
                            ip link add link ${rname}-L2 name ${rname}-L2.$vlan type vlan id $vlan

                        if [ "$group_config" == "Config" ]; then
                            docker exec -d ${group_number}_${rname}router \
                                vtysh -c 'conf t' -c 'interface '${rname}'-L2.'$vlan -c 'ip address '$subnet_router
                            docker exec -d ${group_number}_${rname}router \
                                vtysh -c 'conf t' -c 'interface '${rname}'-L2.'$vlan -c 'ip address '$subnet_router_ipv6
                        fi
                    else
                        if [ "$group_config" == "Config" ]; then
                            docker exec -d ${group_number}_${rname}router \
                                vtysh -c 'conf t' -c 'interface '${rname}'-L2' -c 'ip address '$subnet_router
                            docker exec -d ${group_number}_${rname}router \
                                vtysh -c 'conf t' -c 'interface '${rname}'-L2' -c 'ip address '$subnet_router_ipv6
                        fi
                    fi
                done

                l2_routerid[$property2]=$((${l2_routerid[$property2]} + 1))
            fi
        done

        for ((l = 0; l < n_l2_hosts; l++)); do
            host_l=(${l2_hosts[$l]})
            hname="${host_l[0]}"
            dname="${host_l[1]}"
            l2name="${host_l[2]}"
            sname="${host_l[3]}"
            throughput="${host_l[4]}"
            delay="${host_l[5]}"
            buffer="${host_l[6]}"
            vlan="${host_l[7]}"

            if [ "$group_config" == "Config" ] && [ "$vlan" != "0" ]; then
                docker exec -d "${group_number}""_L2_""${l2name}_${sname}" \
                    ovs-vsctl set port ${group_number}-$hname tag=$vlan
            fi

            if [[ $hname != vpn* ]]; then
                if [ "$group_config" == "Config" ]; then
                    subnet_host=$(subnet_l2 $group_number $((${l2_id["L2-"$l2name]} - 1)) $vlan $((${vlanl2set["L2-"${l2name} - ${vlan}]} + ${l2_routerid["L2-"$l2name]})))
                    subnet_host_ipv6=$(subnet_l2_ipv6 $group_number $((${l2_id["L2-"$l2name]} - 1)) $vlan $((${vlanl2set["L2-"${l2name} - ${vlan}]} + ${l2_routerid["L2-"$l2name]})))

                    get_docker_pid ${group_number}_L2_${l2name}_${hname}
                    PID=$DOCKER_PID
                    create_netns_link

                    # IPv4
                    ip netns exec $PID \
                        ip a add $subnet_host dev ${group_number}-${sname}
                    # IPv6
                    ip netns exec $PID \
                        ip -6 a add $subnet_host_ipv6 dev ${group_number}-${sname}

                    ip netns exec $PID \
                        ip link set dev ${group_number}-${sname} up

                    subnet_gw="$(subnet_l2 ${group_number} $((${l2_id["L2-"$l2name]} - 1)) ${vlan} 1)"
                    subnet_gw_ipv6="$(subnet_l2_ipv6 ${group_number} $((${l2_id["L2-"$l2name]} - 1)) ${vlan} 1)"

                    ip netns exec $PID \
                        ip route add default via ${subnet_gw%/*}

                    ip netns exec $PID \
                        ip -6 route add default via ${subnet_gw_ipv6%/*}
                fi
            fi

            vlanl2set["L2-"${l2name} - ${vlan}]=$((${vlanl2set["L2-"${l2name} - ${vlan}]} + 1))
        done

        trunk_string=''
        for v in "${!vlanset[@]}"; do
            trunk_string=${trunk_string}${v},
        done

        for ((l = 0; l < n_l2_links; l++)); do
            row_l=(${l2_links[$l]})
            l2name1="${row_l[0]}"
            switch1="${row_l[1]}"
            l2name2="${row_l[2]}"
            switch2="${row_l[3]}"
            throughput="${row_l[4]}"
            delay="${row_l[5]}"

            if [ "$group_config" == "Config" ]; then
                docker exec -d "${group_number}""_L2_""${l2name1}_${switch1}" \
                    ovs-vsctl set port ${group_number}-${switch2} trunks=${trunk_string::-1}

                docker exec -d "${group_number}""_L2_""${l2name2}_${switch2}" \
                    ovs-vsctl set port ${group_number}-${switch1} trunks=${trunk_string::-1}
            fi
        done

        for ((l = 0; l < n_l2_switches; l++)); do
            switch_l=(${l2_switches[$l]})
            switch_l=(${l2_switches[$l]})
            l2name="${switch_l[0]}"
            sname="${switch_l[1]}"
            connected="${switch_l[2]}"
            sys_id="${switch_l[3]}"

            if [ "$group_config" == "Config" ]; then
                if [[ $connected != "N/A" ]]; then
                    docker exec -d "${group_number}""_L2_""${l2name}_${sname}" \
                        ovs-vsctl set port ${connected}router trunks=${trunk_string::-1}
                fi
            fi
        done
    fi
done
wait

# ip -6 route show
# ip -6 route show dev tun6to4
