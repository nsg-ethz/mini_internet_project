#!/bin/bash
#
# create all group containers(ssh, routers, hosts, switches)

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"
DOCKERHUB_USER="${2:-thomahol}"
source "${DIRECTORY}"/config/subnet_config.sh
source "${DIRECTORY}"/setup/_parallel_helper.sh

touch "${DIRECTORY}/groups/rpki/krill_containers.txt"

# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt
group_numbers=${#groups[@]}

rpki_location="${DIRECTORY}/groups/rpki"

krill_container_list_file="${rpki_location}/krill_containers.txt"
routinator_container_list_file="${rpki_location}/routinator_containers.txt"
container_list_file="${DIRECTORY}/groups/docker_containers.txt"

# Create empty file or clear its content if the file already exists.
> $krill_container_list_file
> $routinator_container_list_file
> $container_list_file

#create all container
for ((k=0;k<group_numbers;k++)); do
    (
        group_k=(${groups[$k]})
        group_number="${group_k[0]}"
        group_as="${group_k[1]}"
        group_config="${group_k[2]}"
        group_router_config="${group_k[3]}"
        group_layer2_switches="${group_k[5]}"
        group_layer2_hosts="${group_k[6]}"
        group_layer2_links="${group_k[7]}"

        declare -a CONTAINERS
        declare -a KRILL_CONTAINERS
        declare -a ROUTINATOR_CONTAINERS

        echo "Group ${group_number}: creating containers..."

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
                -v "${location}"/restore_configs.sh:/root/restore_configs.sh \
                -v "${location}"/restart_ospfd.sh:/root/restart_ospfd.sh \
                -v /etc/timezone:/etc/timezone:ro \
                -v /etc/localtime:/etc/localtime:ro \
                -v "${DIRECTORY}"/config/welcoming_message.txt:/etc/motd:ro \
                --log-opt max-size=1m --log-opt max-file=3 \
                "${DOCKERHUB_USER}/d_ssh"

            CONTAINERS+=("${group_number}_ssh")

            # start switches
            for ((l=0;l<n_l2_switches;l++)); do

                switch_l=(${l2_switches[$l]})
                l2name="${switch_l[0]}"
                sname="${switch_l[1]}"

                docker run -itd --net='none' --dns="${subnet_dns%/*}" --cap-add=NET_ADMIN \
                    --cpus=2 --pids-limit 1024 --hostname "${sname}" \
                    --name=${group_number}_L2_${l2name}_${sname} \
                    --cap-add=ALL \
                    --cap-drop=SYS_RESOURCE \
                    --sysctl net.ipv4.ip_forward=1 \
                    --sysctl net.ipv4.icmp_ratelimit=0 \
                    --sysctl net.ipv4.fib_multipath_hash_policy=1 \
                    --sysctl net.ipv4.conf.all.rp_filter=0 \
                    --sysctl net.ipv4.conf.default.rp_filter=0 \
                    --sysctl net.ipv4.conf.lo.rp_filter=0 \
                    --sysctl net.ipv4.icmp_echo_ignore_broadcasts=0 \
                    --sysctl net.ipv6.conf.all.disable_ipv6=0 \
                    --sysctl net.ipv6.conf.all.forwarding=1 \
                    --sysctl net.ipv6.icmp.ratelimit=0 \
                    -v /etc/timezone:/etc/timezone:ro \
                    -v /etc/localtime:/etc/localtime:ro \
                    --log-opt max-size=1m --log-opt max-file=3 \
                    "${DOCKERHUB_USER}/d_switch"
                    echo ${group_number}_L2_${l2name}_${sname}

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
                        --sysctl net.ipv6.conf.all.disable_ipv6=0 \
                        --sysctl net.ipv6.icmp.ratelimit=0 \
                        -v /etc/timezone:/etc/timezone:ro \
                        -v /etc/localtime:/etc/localtime:ro \
                        --log-opt max-size=1m --log-opt max-file=3 \
                        $dname

                    CONTAINERS+=("${group_number}""_L2_""${l2name}""_""${hname}")
                fi
            done

            # start routers and hosts
            for ((i=0;i<n_routers;i++)); do
                router_i=(${routers[$i]})
                rname="${router_i[0]}"
                property1="${router_i[1]}"
                property2="${router_i[2]}"
                htype=$(echo $property2 | cut -d ':' -f 1)
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
                    --sysctl net.ipv4.icmp_echo_ignore_broadcasts=0 \
                    --sysctl net.ipv4.tcp_l3mdev_accept=1 \
                    --sysctl net.ipv6.conf.all.disable_ipv6=0 \
                    --sysctl net.ipv6.conf.all.forwarding=1 \
                    --sysctl net.ipv6.icmp.ratelimit=0 \
                    --sysctl net.mpls.conf.lo.input=1 \
                    --sysctl net.mpls.platform_labels=1048575 \
                    --cap-add=ALL \
                    --cap-drop=SYS_RESOURCE \
                    --cpus=2 --pids-limit 100 --hostname "${rname}""_router" \
                    -v "${location}"/looking_glass.txt:/home/looking_glass.txt \
                    -v "${location}"/looking_glass_json.txt:/home/looking_glass_json.txt \
                    -v "${location}"/daemons:/etc/frr/daemons \
                    -v "${location}"/frr.conf:/etc/frr/frr.conf \
                    -v /etc/timezone:/etc/timezone:ro \
                    --log-opt max-size=1m --log-opt max-file=3 \
                    "${DOCKERHUB_USER}/d_router"

                CONTAINERS+=("${group_number}""_""${rname}""router")

                # start host
                if [[ ! -z "${dname}" ]];then
                    container_name="${group_number}_${rname}host"
                    additional_args=()
                    net="none"

                    if [[ "${htype}" == *"krill"* ]]; then
                        KRILL_CONTAINERS+=("${group_number} ${container_name}")
                        krill_auth_token=$(<"${DIRECTORY}/groups/g${group_number}/krill/krill_token.txt")
                        additional_args+=("--add-host" "rpki-server.group${group_number}:127.0.0.1")
                        additional_args+=("-e" "KRILL_CLI_TOKEN=${krill_auth_token}")
                        additional_args+=("-v" "${rpki_location}/tals:/var/krill/tals")
                        additional_args+=("-v" "${rpki_location}/root.crt:/usr/local/share/ca-certificates/root.crt:ro")
                        additional_args+=("-v" "${DIRECTORY}/groups/g${group_number}/krill/data:/var/krill/data")
                        additional_args+=("-v" "${DIRECTORY}/groups/g${group_number}/krill/krill.includesprivatekey.pem:/etc/ssl/certs/cert.includesprivatekey.pem:ro")
                        additional_args+=("-v" "${DIRECTORY}/groups/g${group_number}/krill/krill.crt:/var/krill/data/ssl/cert.pem:ro")
                        additional_args+=("-v" "${DIRECTORY}/groups/g${group_number}/krill/krill.key:/var/krill/data/ssl/key.pem:ro")
                        additional_args+=("-v" "${DIRECTORY}/groups/g${group_number}/krill/krill.conf:/var/krill/krill.conf:ro")
                        additional_args+=("-v" "${DIRECTORY}/groups/g${group_number}/krill/setup.sh:/home/setup.sh:ro")
                        additional_args+=("-v" "${DIRECTORY}/config/roas:/var/krill/roas:ro")
                        # Use bridge network for krill in order to connect to the web proxy container
                        # and use an https connection from the ouside world to reach the krill website
                        additional_args+=("-p" "3080:3080")
                        net="bridge"
                        # Enable traefik
                        additional_args+=("-l" "traefik.enable=true")
                        additional_args+=("-l" "traefik.http.routers.krill.entrypoints=krill")
                    elif [[ "${htype}" == *"routinator"* ]]; then
                        ROUTINATOR_CONTAINERS+=("${group_number} ${container_name}")
                        additional_args+=("-v" "${rpki_location}/root.crt:/usr/local/share/ca-certificates/root.crt:ro")
                        additional_args+=("-v" "${rpki_location}/tals:/root/.rpki-cache/tals:ro")
                        additional_args+=("-v" "${DIRECTORY}/groups/g${group_number}/rpki_exceptions.json:/root/rpki_exceptions.json")
                        additional_args+=("-v" "${DIRECTORY}/groups/g${group_number}/rpki_exceptions_autograder.json:/root/rpki_exceptions_autograder.json")
                    fi

                    docker run -itd --network "$net" --dns="${subnet_dns%/*}"  \
                        --name="${container_name}" --cap-add=NET_ADMIN \
                        --cpus=2 --pids-limit 100 --hostname "${rname}""_host" \
                        --sysctl net.ipv4.icmp_ratelimit=0 \
                        --sysctl net.ipv4.icmp_echo_ignore_broadcasts=0 \
                        --sysctl net.ipv6.conf.all.disable_ipv6=0 \
                        --sysctl net.ipv6.icmp.ratelimit=0 \
                        -v /etc/timezone:/etc/timezone:ro \
                        -v /etc/localtime:/etc/localtime:ro \
                        --log-opt max-size=1m --log-opt max-file=3 \
                        "${additional_args[@]}" \
                        $dname
                        # add this for bgpsimple -v ${DIRECTORY}/docker_images/host/bgpsimple.pl:/home/bgpsimple.pl \

                    CONTAINERS+=("${container_name}")
                fi
            done

        elif [ "${group_as}" = "IXP" ];then

            location="${DIRECTORY}"/groups/g"${group_number}"
            docker run -itd --net='none' --name="${group_number}""_IXP" \
                --pids-limit 200 --hostname "${group_number}""_IXP" \
                -v "${location}"/daemons:/etc/quagga/daemons \
                --privileged \
                --sysctl net.ipv4.ip_forward=1 \
                --sysctl net.ipv4.icmp_ratelimit=0 \
                --sysctl net.ipv4.fib_multipath_hash_policy=1 \
                --sysctl net.ipv4.conf.all.rp_filter=0 \
                --sysctl net.ipv4.conf.default.rp_filter=0 \
                --sysctl net.ipv4.conf.lo.rp_filter=0 \
                --sysctl net.ipv4.icmp_echo_ignore_broadcasts=0 \
                --sysctl net.ipv6.conf.all.disable_ipv6=0 \
                --sysctl net.ipv6.conf.all.forwarding=1 \
                --sysctl net.ipv6.icmp.ratelimit=0 \
                -v /etc/timezone:/etc/timezone:ro \
                -v /etc/localtime:/etc/localtime:ro \
                -v "${location}"/looking_glass.txt:/home/looking_glass.txt \
                --log-opt max-size=1m --log-opt max-file=3 \
                "${DOCKERHUB_USER}/d_ixp"

            CONTAINERS+=("${group_number}""_IXP")
        fi

        printf '%b\n' "${ROUTINATOR_CONTAINERS[@]}" >> $routinator_container_list_file
        printf '%b\n' "${KRILL_CONTAINERS[@]}" >> $krill_container_list_file
        printf '%b\n' "${CONTAINERS[@]}" >> $container_list_file

        echo "Group ${group_number}: ${#CONTAINERS[@]} containers created!"
    ) &

    wait_if_n_tasks_are_running
done

wait

# Read container list from file
readarray -t CONTAINERS < $container_list_file

# Cache the docker pid to avoid calling docker inspect multiple times
# Access via setup/ovs-docker.sh get_docker_pid
readarray -t PIDS <<< $(docker inspect -f '{{.State.Pid}}' "${CONTAINERS[@]}")
declare -A DOCKER_TO_PID
for ((i=0;i<${#CONTAINERS[@]};++i)); do
    if [[ $(lsb_release -rs) == 16* ]]; then
        DOCKER_TO_PID["${CONTAINERS[$i]}"]=$(echo $PIDS | cut -f $(($i+1)) -d ' ')
    else
        DOCKER_TO_PID["${CONTAINERS[$i]}"]=${PIDS[$i]}
    fi
done

declare -p DOCKER_TO_PID > ${DIRECTORY}/groups/docker_pid.map