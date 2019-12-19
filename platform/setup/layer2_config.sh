#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"
source "${DIRECTORY}"/config/subnet_config.sh

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
    group_config="${group_k[2]}"


    if [ "${group_as}" != "IXP" ];then

        for ((i=0;i<n_routers;i++)); do
            router_i=(${routers[$i]})
            rname="${router_i[0]}"
            property1="${router_i[1]}"
            property2="${router_i[2]}"
            if [[ "${property2}" == *L2* ]];then

                declare -A vlanset
                for ((l=0;l<n_l2_hosts;l++)); do
                    host_l=(${l2_hosts[$l]})
                    vlan="${host_l[4]}"
                    vlanset[$vlan]=0
                done

                for vlan in "${!vlanset[@]}"
                do
                    docker exec -d ${group_number}_${rname}router \
                        vconfig add ${rname}-L2 $vlan
                    docker exec -d ${group_number}_${rname}router \
                        ifconfig ${rname}-L2.$vlan up
                done
            fi
        done


        for ((l=0;l<n_l2_hosts;l++)); do
            host_l=(${l2_hosts[$l]})
            hname="${host_l[0]}"
            sname="${host_l[1]}"
            throughput="${host_l[2]}"
            delay="${host_l[3]}"
            vlan="${host_l[4]}"
            l2name=$(echo $sname | cut -f 1 -d '-')

            l2_id=0
            for ((i=0;i<n_routers;i++)); do
                router_i=(${routers[$i]})
                property2="${router_i[2]}"

                if [[ "${property2}" == *L2* ]];then
                    l2tmp=$(echo $property2 | cut -f 2 -d '-')
                    if [[ "$l2tmp" == "$l2name" ]]; then
                        break
                    else
                        l2_id=$(($l2_id+1))
                    fi

                fi
            done

            if [ "$group_config" == "Config" ]; then
                docker exec -d "${group_number}""_L2_""${sname}" \
                    ovs-vsctl set port ${rname}-$hname tag=$vlan
            fi

            vlanset[$vlan]=$((${vlanset[$vlan]}+1)) 

            if [[ $hname != vpn* ]]; then
                if [ "$group_config" == "Config" ]; then
                    docker exec -d ${group_number}_L2_${sname}_${hname} \
                        ifconfig ${group_number}-${sname} $(subnet_l2_router $group_number $l2_id $vlan $((${vlanset[$vlan]}+1))) up

                    docker exec -d ${group_number}_L2_${sname}_${hname} \
                        route add default gw $group_number.$((200+$l2_id)).${vlan}.1
                fi
            fi
        done

        trunk_string=''
        for v in "${!vlanset[@]}"
        do
            trunk_string=${trunk_string}${v},
        done

        for ((l=0;l<n_l2_links;l++)); do
            row_l=(${l2_links[$l]})
            switch1="${row_l[0]}"
            switch2="${row_l[1]}"
            throughput="${row_l[2]}"
            delay="${row_l[3]}"

            if [ "$group_config" == "Config" ]; then
                docker exec -d "${group_number}""_L2_""${switch1}" \
                    ovs-vsctl set port ${rname}-${switch2} trunks=${trunk_string::-1}

                    docker exec -d "${group_number}""_L2_""${switch2}" \
                    ovs-vsctl set port ${rname}-${switch1} trunks=${trunk_string::-1}
            fi
        done
    fi
done
