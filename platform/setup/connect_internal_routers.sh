#!/bin/bash
#
# Connects the internal routers in each group and configure link properties.
#

# sanity check
# set -x
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

readarray ASConfig < "${DIRECTORY}"/config/AS_config.txt
GroupNumber=${#ASConfig[@]}

for ((k = 0; k < GroupNumber; k++)); do
    (
        GroupK=(${ASConfig[$k]})               # group config file array
        GroupAS="${GroupK[0]}"                 # ASN
        GroupType="${GroupK[1]}"               # IXP/AS
        GroupInternalLinkConfig="${GroupK[4]}" # Group internal link config file

        if [ "${GroupType}" != "IXP" ]; then

            readarray InternalLinks < "${DIRECTORY}/config/$GroupInternalLinkConfig"
            IntLinkNumber=${#InternalLinks[@]}

            for ((i = 0; i < IntLinkNumber; i++)); do
                # cannot run each group in parallel as the same router can be accessed by multiple links
                IntLinkI=(${InternalLinks[$i]}) # internal link row
                RegionA="${IntLinkI[0]}"        # region A
                RegionB="${IntLinkI[1]}"        # region B
                Throughput="${IntLinkI[2]}"     # throughput
                Delay="${IntLinkI[3]}"          # delay
                Buffer="${IntLinkI[4]}"         # buffer latency (in ms)
                connect_one_internal_routers "${GroupAS}" "${RegionA}" "${RegionB}" "${Throughput}" "${Delay}" "${Buffer}"
            done
        echo "Connected internal routers in group ${GroupAS}"
        fi
    )
done
wait
