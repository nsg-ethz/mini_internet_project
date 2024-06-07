#!/bin/bash
#
# Connects the measurement, dns and matrix services
#

# sanity check
# set -e
set -o errexit
set -o pipefail
set -o nounset

# make sure the script is executed with root privileges
if (($UID != 0)); then
    echo "$0 needs to be run as root"
    exit 1
fi

# print the usage if not enough arguments are provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <directory>"
    exit 1
fi


DIRECTORY=$(readlink -f $1)
source "${DIRECTORY}"/config/variables.sh
source "${DIRECTORY}"/config/subnet_config.sh
source "${DIRECTORY}"/setup/_parallel_helper.sh
source "${DIRECTORY}"/groups/docker_pid.map
source "${DIRECTORY}"/setup/_connect_utils.sh
readarray ASConfig < "${DIRECTORY}"/config/AS_config.txt
GroupNumber=${#ASConfig[@]}

# check if each service is required
MeasureRequired=$(check_service_is_required "MEASUREMENT")
DNSRequired=$(check_service_is_required "DNS")
MatrixRequired=$(check_service_is_required "MATRIX")

# start measurement container
# ssh is configured for remote access, and we add direct access below.
if [[ "$MeasureRequired" == "True" ]]; then
    SubnetDNS="$(subnet_router_DNS -1 "dns-measurement")"
    SubNetSsh="$(subnet_ext_sshContainer -1 "MEASUREMENT")"
    SshBridge="ssh_bridge"
    docker run -itd --dns="${SubnetDNS%/*}" \
        --sysctl net.ipv4.icmp_ratelimit=0 \
        --sysctl net.ipv4.ip_forward=0 \
        --name="MEASUREMENT" --hostname="MEASUREMENT" \
        --cpus=2 --pids-limit 100 \
        -v /etc/timezone:/etc/timezone:ro \
        -v /etc/localtime:/etc/localtime:ro \
        -v \
        "${DIRECTORY}"/config/measurement_welcome_message.txt:/etc/motd:rw \
        --cap-add=NET_ADMIN \
        --network="bridge" -p 2099:22 \
        "${DOCKERHUB_PREFIX}d_measurement" > /dev/null

    # connect to ssh network and rename interface to ssh in the ssh container
    docker network connect --ip="${SubNetSsh%/*}" $SshBridge "MEASUREMENT"
    docker exec MEASUREMENT ip link set dev eth1 down
    docker exec MEASUREMENT ip link set dev eth1 name ssh
    docker exec MEASUREMENT ip link set dev ssh up

    # cache the container PID
    DOCKER_TO_PID['MEASUREMENT']=$(docker inspect -f '{{.State.Pid}}' MEASUREMENT)
    declare -p DOCKER_TO_PID > ${DIRECTORY}/groups/docker_pid.map

    # add ssh password
    docker cp "${DIRECTORY}"/groups/authorized_keys MEASUREMENT:/root/.ssh/authorized_keys > /dev/null
    Passwd="$(openssl rand -hex 8)"
    echo "${Passwd}" >> "${DIRECTORY}"/groups/ssh_measurement.txt
    echo -e ""${Passwd}"\n"${Passwd}"" | docker exec -i MEASUREMENT passwd root > /dev/null

    # TODO DEPRECATED
    # # update the launching script
    # docker cp "${DIRECTORY}"/docker_images/measurement/launch_traceroute.sh \
    #     MEASUREMENT:/root/launch_traceroute.sh > /dev/null
else
    echo "MEASUREMENT service is not required"
fi

# start matrix container
if [[ "$MatrixRequired" == "True" ]]; then
    MatrixConfigDir="${DIRECTORY}"/groups/matrix/
    mkdir -p ${MatrixConfigDir}

    touch "$MatrixConfigDir"/destination_ips.txt
    touch "$MatrixConfigDir"/connectivity.txt
    touch "$MatrixConfigDir"/stats.txt

    docker run -itd --net='none' --name="MATRIX" --hostname="MATRIX" \
        --privileged \
        --sysctl net.ipv4.icmp_ratelimit=0 \
        --sysctl net.ipv4.ip_forward=0 \
        -v /etc/timezone:/etc/timezone:ro \
        -v /etc/localtime:/etc/localtime:ro \
        -v "${MatrixConfigDir}"/destination_ips.txt:/home/destination_ips.txt \
        -v "${MatrixConfigDir}"/connectivity.txt:/home/connectivity.txt \
        -v "${MatrixConfigDir}"/stats.txt:/home/stats.txt \
        -e "UPDATE_FREQUENCY=${MATRIX_FREQUENCY}" \
        -e "CONCURRENT_PINGS=${MATRIX_CONCURRENT_PINGS}" \
        -e "PING_FLAGS=${MATRIX_PING_FLAGS}" \
        "${DOCKERHUB_PREFIX}d_matrix" > /dev/null

    if $MATRIX_PAUSE_AFTER_START; then
        docker pause MATRIX
    fi

    # cache the container PID
    DOCKER_TO_PID['MATRIX']=$(docker inspect -f '{{.State.Pid}}' MATRIX)
    declare -p DOCKER_TO_PID > ${DIRECTORY}/groups/docker_pid.map
else
    echo "MATRIX service is not required"
fi

# start dns container
if [[ "$DNSRequired" == "True" ]]; then
    # create dns container, copy files generated from dns_config.sh into the
    # container before starting it.
    docker create --net='none' --name="DNS" --hostname="DNS" --privileged \
        --sysctl net.ipv4.ip_forward=0 \
        -v /etc/timezone:/etc/timezone:ro \
        -v /etc/localtime:/etc/localtime:ro \
        "${DOCKERHUB_PREFIX}d_dns"

    docker cp "${DIRECTORY}"/groups/dns/group_config DNS:/etc/bind/group_config > /dev/null
    docker cp "${DIRECTORY}"/groups/dns/zones DNS:/etc/bind/zones > /dev/null
    docker cp "${DIRECTORY}"/groups/dns/named.conf.local DNS:/etc/bind/named.conf.local > /dev/null
    docker cp "${DIRECTORY}"/groups/dns/named.conf.options DNS:/etc/bind/named.conf.options > /dev/null

    docker start DNS

    # cache the container PID
    DOCKER_TO_PID['DNS']=$(docker inspect -f '{{.State.Pid}}' DNS)
    declare -p DOCKER_TO_PID > ${DIRECTORY}/groups/docker_pid.map

    # create the virtual interface
    docker exec DNS ip link add name dns type dummy
    docker exec DNS ip addr add "$(subnet_router_DNS -1 "dns")" dev dns
    docker exec DNS ip link set dns up

else
    echo "DNS service is not required"
fi

for ((k = 0; k < GroupNumber; k++)); do
    GroupK=(${ASConfig[$k]})         # group config file array
    GroupAS="${GroupK[0]}"           # AS number
    GroupType="${GroupK[1]}"         # IXP/AS
    GroupRouterConfig="${GroupK[3]}" # L3 router config file

    if [ "${GroupType}" != "IXP" ]; then

        readarray Routers < "${DIRECTORY}"/config/$GroupRouterConfig
        RouterNumber=${#Routers[@]}

        # Direct ssh access to the measurement container for each group:
        # connect the group ssh container to the measurement container
        if [[ "$MeasureRequired" == "True" ]]; then
            PubKey=$(cat "${DIRECTORY}"/groups/g${GroupAS}/id_rsa.pub)
            connect_one_ssh_measurement "${GroupAS}" "${PubKey}"
            # echo "${GroupAS}: connected MEASUREMENT to SSH"
        fi

        for ((i = 0; i < RouterNumber; i++)); do
            RouterI=(${Routers[$i]})      # router config file array
            RouterRegion="${RouterI[0]}"  # region name
            RouterService="${RouterI[1]}" # measurement/matrix/dns

            # connect the measurement container to each group
            if [[ "$RouterService" == "MEASUREMENT" ]]; then
                connect_one_measurement "${GroupAS}" "${RouterRegion}"
                # echo "${GroupAS}: connected MEASUREMENT to network"
            fi

            # record the destination IP
            if [[ "$RouterService" == "MATRIX_TARGET" ]]; then
                TargetSubnet="$(subnet_host_router ${GroupAS} ${i} "host")"
                echo $GroupAS" "${TargetSubnet%/*} >> "${MatrixConfigDir}"/destination_ips.txt
            fi

            # connect the matrix container to each group
            if [[ "$RouterService" == "MATRIX" ]]; then
                connect_one_matrix "${GroupAS}" "${RouterRegion}"
                # echo "${GroupAS}: connected MATRIX"
            fi

            # # connect the dns container to each group
            if [[ "$RouterService" == "DNS" ]]; then
                connect_one_dns "${GroupAS}" "${RouterRegion}"
                # echo "${GroupAS}: connected DNS"
            fi
        done

        echo "Group ${GroupAS} connected to services."
    fi
done

# connect measurement to dns
if [[ "$DNSRequired" == "True" ]]; then
    connect_service_interfaces \
        "DNS" "measurement" "$(subnet_router_DNS -1 "dns-measurement")" \
        "MEASUREMENT" "dns" "$(subnet_router_DNS -1 "measurement")" \
        -1  # -1 to set up IPs in both containers but no default routes.
fi
