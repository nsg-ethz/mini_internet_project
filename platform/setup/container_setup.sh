#!/bin/bash
#
# create all group containers(ssh, routers, hosts, switches)

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"
source "${DIRECTORY}"/config/subnet_config.sh

# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt
group_numbers=${#groups[@]}

declare -a CONTAINERS

#create all container
for ((k=0;k<group_numbers;k++)); do
    group_k=(${groups[$k]})
    group_number="${group_k[0]}"
    group_as="${group_k[1]}"
    group_config="${group_k[2]}"
    group_router_config="${group_k[3]}"
    group_layer2_switches="${group_k[5]}"
    group_layer2_hosts="${group_k[6]}"
    group_layer2_links="${group_k[7]}"

    echo "creating containers for group: ""${group_number}"

    if [ "${group_as}" != "IXP" ];then

        readarray routers < "${DIRECTORY}"/config/$group_router_config
        readarray l2_switches < "${DIRECTORY}"/config/$group_layer2_switches
        readarray l2_hosts < "${DIRECTORY}"/config/$group_layer2_hosts
        n_routers=${#routers[@]}
        n_l2_switches=${#l2_switches[@]}
        n_l2_hosts=${#l2_hosts[@]}

        location="${DIRECTORY}"/groups/g"${group_number}"
        subnet_dns="$(subnet_router_DNS "${group_number}" "dns")"

        # start ssh container
        docker run -itd --net='none'  --name="${group_number}""_ssh" \
            --cpus=2 --pids-limit 100 --hostname="g${group_number}-proxy" --cap-add=NET_ADMIN \
            -v "${location}"/goto.sh:/root/goto.sh  \
            -v "${location}"/save_configs.sh:/root/save_configs.sh \
            -v /etc/timezone:/etc/timezone:ro \
            -v /etc/localtime:/etc/localtime:ro \
            -v "${DIRECTORY}"/config/welcoming_message.txt:/etc/motd:ro \
            thomahol/d_ssh

        CONTAINERS+=("${group_number}_ssh")

        # start switches
        for ((l=0;l<n_l2_switches;l++)); do

            switch_l=(${l2_switches[$l]})
            l2name="${switch_l[0]}"
            sname="${switch_l[1]}"

            docker run -itd --net='none' --dns="${subnet_dns%/*}" --cap-add=NET_ADMIN \
                --cpus=2 --pids-limit 100 --hostname "${sname}" \
                --name=${group_number}_L2_${l2name}_${sname} \
                --sysctl net.ipv4.ip_forward=1 \
                --sysctl net.ipv4.icmp_ratelimit=0 \
                --sysctl net.ipv4.fib_multipath_hash_policy=1 \
                --sysctl net.ipv4.conf.all.rp_filter=0 \
                --sysctl net.ipv4.conf.default.rp_filter=0 \
                --sysctl net.ipv4.conf.lo.rp_filter=0 \
                --sysctl net.ipv4.icmp_echo_ignore_broadcasts=0 \
                -v /etc/timezone:/etc/timezone:ro \
                -v /etc/localtime:/etc/localtime:ro thomahol/d_switch

            CONTAINERS+=(${group_number}_L2_${l2name}_${sname})
        done

        # start hosts in l2 network
        for ((l=0;l<n_l2_hosts;l++)); do
            host_l=(${l2_hosts[$l]})
            hname="${host_l[0]}"
            dname="${host_l[1]}"
            l2name="${host_l[2]}"
            sname="${host_l[3]}"

            if [[ $hname != vpn* ]]; then
                docker run -itd --net='none' --dns="${subnet_dns%/*}" --cap-add=NET_ADMIN \
                    --cpus=2 --pids-limit 100 --hostname "${hname}" \
                    --name="${group_number}""_L2_""${l2name}""_""${hname}" \
                    --sysctl net.ipv4.icmp_ratelimit=0 \
                    --sysctl net.ipv4.icmp_echo_ignore_broadcasts=0 \
                    -v /etc/timezone:/etc/timezone:ro \
                    -v /etc/localtime:/etc/localtime:ro $dname

                CONTAINERS+=("${group_number}""_L2_""${l2name}""_""${hname}")
            fi
        done

        # start routers and hosts
        for ((i=0;i<n_routers;i++)); do
            router_i=(${routers[$i]})
            rname="${router_i[0]}"
            property1="${router_i[1]}"
            property2="${router_i[2]}"
            dname=$(echo $property2 | cut -d ':' -f 2)

            location="${DIRECTORY}"/groups/g"${group_number}"/"${rname}"

            # start router
            docker run -itd --net='none'  --dns="${subnet_dns%/*}" \
                --name="${group_number}""_""${rname}""router" \
                --sysctl net.ipv4.ip_forward=1 \
                --sysctl net.ipv4.icmp_ratelimit=0 \
                --sysctl net.ipv4.fib_multipath_hash_policy=1 \
                --sysctl net.ipv4.conf.all.rp_filter=0 \
                --sysctl net.ipv4.conf.default.rp_filter=0 \
                --sysctl net.ipv4.conf.lo.rp_filter=0 \
                --sysctl net.mpls.conf.lo.input=1 \
                --sysctl net.ipv4.icmp_echo_ignore_broadcasts=0 \
                --sysctl net.mpls.platform_labels=1048575 \
                --privileged \
                --cpus=2 --pids-limit 100 --hostname "${rname}""_router" \
                -v "${location}"/looking_glass.txt:/home/looking_glass.txt \
                -v "${location}"/daemons:/etc/frr/daemons \
                -v "${location}"/frr.conf:/etc/frr/frr.conf \
                -v /etc/timezone:/etc/timezone:ro \
                -v /etc/localtime:/etc/localtime:ro thomahol/d_router

            CONTAINERS+=("${group_number}""_""${rname}""router")

            # start host
            if [[ "${property2}" == host* ]];then
                docker run -itd --net='none' --dns="${subnet_dns%/*}"  \
                    --name="${group_number}""_""${rname}""host" --cap-add=NET_ADMIN \
                    --cpus=2 --pids-limit 100 --hostname "${rname}""_host" \
                    --sysctl net.ipv4.icmp_ratelimit=0 \
                    -v /etc/timezone:/etc/timezone:ro \
                    -v /etc/localtime:/etc/localtime:ro $dname
                    # add this for bgpsimple -v ${DIRECTORY}/docker_images/host/bgpsimple.pl:/home/bgpsimple.pl \

                CONTAINERS+=("${group_number}""_""${rname}""host")
            fi
        done

    elif [ "${group_as}" = "IXP" ];then

        location="${DIRECTORY}"/groups/g"${group_number}"
        docker run -itd --net='none' --name="${group_number}""_IXP" \
            --pids-limit 100 --hostname "${group_number}""_IXP" \
            -v "${location}"/daemons:/etc/quagga/daemons \
            --privileged \
            --sysctl net.ipv4.ip_forward=1 \
            --sysctl net.ipv4.icmp_ratelimit=0 \
            --sysctl net.ipv4.fib_multipath_hash_policy=1 \
            --sysctl net.ipv4.conf.all.rp_filter=0 \
            --sysctl net.ipv4.conf.default.rp_filter=0 \
            --sysctl net.ipv4.conf.lo.rp_filter=0 \
            --sysctl net.ipv4.icmp_echo_ignore_broadcasts=0 \
            -v /etc/timezone:/etc/timezone:ro \
            -v /etc/localtime:/etc/localtime:ro \
            thomahol/d_ixp

       CONTAINERS+=("${group_number}""_IXP")
    fi
done

# Cache the docker pid to avoid calling docker inspect multiple times
# Access via setup/ovs-docker.sh get_docker_pid
readarray -t PIDS <<< $(docker inspect -f '{{.State.Pid}}' "${CONTAINERS[@]}")
declare -A DOCKER_TO_PID
for ((i=0;i<${#CONTAINERS[@]};++i)); do
    DOCKER_TO_PID["${CONTAINERS[$i]}"]=${PIDS[$i]}
done
declare -p DOCKER_TO_PID > ${DIRECTORY}/groups/docker_pid.map
