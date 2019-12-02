#!/bin/bash
#
# delete links between hosts and switches
# what switch a host is connected is defined in config/layer2_hosts_config.txt
# links between switches are defined in config/layer2_links_config.txt

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
                echo -n "-- --if-exists del-br "${br_name}" " >> "${DIRECTORY}"/ovs_command.txt

                # for ((l=0;l<n_l2_switches;l++)); do
                #     switch_l=(${l2_switches[$l]})
                #     sname="${switch_l[0]}"
                #     connected="${switch_l[1]}"
                #     sys_id="${switch_l[2]}"
                #
                #     if [ "${connected}" == "router" ];then
                #         br_name="l2-""${group_number}""-""${rname}"
                #
                #         echo -n "-- --if-exists del-br "${br_name}" " >> "${DIRECTORY}"/ovs_command.txt
                #     fi
                # done
                #
                # for ((l=0;l<n_l2_links;l++)); do
                #     row_l=(${l2_links[$l]})
                #     switch1="${row_l[0]}"
                #     switch2="${row_l[1]}"
                #     throughput="${row_l[2]}"
                #     delay="${row_l[3]}"
                #
                #     br_name="l2-""${group_number}""-""${rname}""-""${l}"
                #
                #     echo -n "-- --if-exists del-br "${br_name}" " >> "${DIRECTORY}"/ovs_command.txt
                #
                # done
                #
                # for ((l=0;l<n_l2_hosts;l++)); do
                #     host_l=(${l2_hosts[$l]})
                #     hname="${host_l[0]}"
                #     sname="${host_l[1]}"
                #     throughput="${host_l[2]}"
                #     delay="${host_l[3]}"
                #
                #     br_name="l2-""${group_number}""-""${rname}""-""$((l+n_l2_links))"
                #
                #     echo -n "-- --if-exists del-br "${br_name}" " >> "${DIRECTORY}"/ovs_command.txt
                #
                # done
            fi
        done
    fi
done

modprobe --remove 8021q
