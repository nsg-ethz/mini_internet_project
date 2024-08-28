#!/bin/bash
#
# Connects the ssh links for each group
#

# sanity check
trap 'exit 1' ERR
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

DIRECTORY=$1
source "${DIRECTORY}"/config/subnet_config.sh
source "${DIRECTORY}"/setup/_parallel_helper.sh
source "${DIRECTORY}"/groups/docker_pid.map
source "${DIRECTORY}"/setup/_connect_utils.sh

# Generate TA key pair
ssh-keygen -t rsa -b 4096 -C "ta key" -P "" -f "groups/id_rsa" -q
# We need to distribute the key to the TAs, so we make it readable.
chmod +r groups/id_rsa
cp groups/id_rsa.pub groups/authorized_keys

readarray ASConfig < "${DIRECTORY}"/config/AS_config.txt
GroupNumber=${#ASConfig[@]}

for ((k = 0; k < GroupNumber; k++)); do
    GroupK=(${ASConfig[$k]})           # group config file array
    GroupAS="${GroupK[0]}"             # ASN
    GroupType="${GroupK[1]}"           # IXP/AS
    GroupRouterConfig="${GroupK[3]}"   # Group router config file
    GroupL2SwitchConfig="${GroupK[5]}" # Group L2 switch config file
    GroupL2HostConfig="${GroupK[6]}"   # Group L2 host config file

    GroupDirectory="${DIRECTORY}/groups/g${GroupAS}"

    if [ "${GroupType}" != "IXP" ]; then

        readarray Routers < "${DIRECTORY}"/config/$GroupRouterConfig
        readarray L2Switches < "${DIRECTORY}/config/$GroupL2SwitchConfig"
        readarray L2Hosts < "${DIRECTORY}/config/$GroupL2HostConfig"

        RouterNumber=${#Routers[@]}
        L2SwitchNumber=${#L2Switches[@]}
        L2HostNumber=${#L2Hosts[@]}

        # generate ssh key
        GroupSSHContainer="${GroupAS}_ssh"
        ssh-keygen -t rsa -b 4096 -C "internal key group ${GroupAS}" -P "" -f "groups/g${GroupAS}/id_rsa" -q

        docker cp "${GroupDirectory}"/id_rsa "${GroupAS}"_ssh:/root/.ssh/id_rsa > /dev/null
        docker cp "${GroupDirectory}"/id_rsa.pub "${GroupAS}"_ssh:/root/.ssh/id_rsa.pub > /dev/null

        # authorize TA key
        docker cp "${DIRECTORY}"/groups/authorized_keys "${GroupSSHContainer}:/root/.ssh/authorized_keys" > /dev/null
        # docker cp "${DIRECTORY}"/groups/authorized_keys "${GroupSSHContainer}:/etc/ssh/authorized_keys" > /dev/null

        # set password for the ssh container login
        Passwd=$(awk "\$1 == \"${GroupAS}\" { print \$2 }" "${DIRECTORY}/groups/passwords.txt")
        echo -e ""${Passwd}"\n"${Passwd}"" | docker exec -i "${GroupSSHContainer}" passwd root > /dev/null
        # reload sshd config
        docker exec "${GroupSSHContainer}" bash -c "kill -HUP \$(cat /var/run/sshd.pid)"

        # add ssh public key in each router and L3 host container
        for ((i = 0; i < RouterNumber; i++)); do
            RouterI=(${Routers[$i]})                               # router row
            RouterRegion="${RouterI[0]}"                           # router region
            HostImage=$(echo "${RouterI[2]}" | cut -s -d ':' -f 2) # docker image
            RouterCommand="${RouterI[3]}"                          # vtysh / linux

            # copy the public key to the router container
            RouterContainer="${GroupAS}_${RouterRegion}router"
            # for all-in-one AS, this could copy the same router multiple times
            # but in general the overhead should be small
            docker cp "${GroupDirectory}"/id_rsa.pub "${RouterContainer}:/root/.ssh/authorized_keys" > /dev/null

            # copy the public key to the L3 host container
            HostSuffix=""
            if [[ ${#RouterI[@]} -gt 4 && "${RouterI[4]}" == "ALL" ]]; then
                HostSuffix="${i}"
            fi

            if [[ -n "${HostImage}" ]]; then
                HostContainer="${GroupAS}_${RouterRegion}host${HostSuffix}"
                docker cp "${GroupDirectory}"/id_rsa.pub "${HostContainer}:/root/.ssh/authorized_keys" > /dev/null
                # reload ssh config
                docker exec "${HostContainer}" bash -c "kill -HUP \$(cat /var/run/sshd.pid)"
            fi
        done

        # add ssh public key in each L2 switch container
        for ((i = 0; i < L2SwitchNumber; i++)); do
            L2SwitchI=(${L2Switches[$i]}) # L2 switch row
            DCName="${L2SwitchI[0]}"      # DC name
            SWName="${L2SwitchI[1]}"      # switch name

            SwCtnName="${GroupAS}_L2_${DCName}_${SWName}"

            docker cp "${GroupDirectory}"/id_rsa.pub "${SwCtnName}:/root/.ssh/authorized_keys" > /dev/null
        done

        # add ssh public key in each L2 host container
        for ((i = 0; i < L2HostNumber; i++)); do
            L2HostI=(${L2Hosts[$i]}) # L2 host row
            HostName="${L2HostI[0]}" # host name
            DCName="${L2HostI[2]}"   # DC name
            SWName="${L2HostI[3]}"   # switch name

            # skip vpn
            if [[ ! ${HostName} == vpn* ]]; then
                HostContainer="${GroupAS}_L2_${DCName}_${HostName}"
                docker cp "${GroupDirectory}"/id_rsa.pub "${HostContainer}:/root/.ssh/authorized_keys" > /dev/null
                # reload ssh config
                docker exec "${HostContainer}" bash -c "kill -HUP \$(cat /var/run/sshd.pid)"
            fi
        done
    echo "Configured SSH in group ${GroupAS}"
    fi
done
wait # wait for all parallel tasks to finish
