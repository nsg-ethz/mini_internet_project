#!/bin/bash
#
# Connects the external routers across grouops and configure link properties.
#

# sanity check
# set -x
trap 'exit 1' ERR # catch more error
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

# connect links in parallel in the given link group files
connect_one_link_group() {

    # check enough arguments are provided
    if [ "$#" -ne 1 ]; then
        echo "Usage: connect_one_link_group <ExtLinkFile>"
        exit 1
    fi

    CurrentLinkFile=$1
    readarray CurrentLinks < "${CurrentLinkFile}"
    LinkNumber=${#CurrentLinks[@]}
    for ((i = 0; i < LinkNumber; i++)); do
        (
            LinkI=(${CurrentLinks[$i]}) # external link row
            AS1="${LinkI[0]}"           # AS1
            Region1="${LinkI[1]}"       # region 1 in AS1
            AS2="${LinkI[2]}"           # AS2
            Region2="${LinkI[3]}"       # region 2 in AS2
            Throughput="${LinkI[4]}"    # throughput
            Delay="${LinkI[5]}"         # delay
            Buffer="${LinkI[6]}"        # buffer latency (in ms)

            connect_one_external_routers "${AS1}" "${Region1}" "${AS2}" "${Region2}" "${Throughput}" "${Delay}" "${Buffer}"
        ) & # all links in the same group can be parallelized as they don't share the same namespace
        # wait_if_n_tasks_m_cpu_and_k_interrupts_are_running
        wait_if_n_tasks_are_running # there is only one link connection in the process, safe
    done
    wait
}

DIRECTORY=$1
source "${DIRECTORY}"/config/subnet_config.sh
source "${DIRECTORY}"/setup/_parallel_helper.sh
source "${DIRECTORY}"/groups/docker_pid.map
source "${DIRECTORY}"/setup/_connect_utils.sh
# readarray ExternalLinks < "${DIRECTORY}"/config/aslevel_links.txt

# first compute independent links that can be parallelized
python3 "${DIRECTORY}"/setup/_compute_independent_ext_links.py "${DIRECTORY}"

# for each aslevel_links_*.txt file
for CurrentLinkFile in "${DIRECTORY}"/groups/aslevel_links/aslevel_links_*.txt; do
    connect_one_link_group "${CurrentLinkFile}" # different link groups cannot be parallelized
    echo "Connected external links in ${CurrentLinkFile}"
done
wait

# delete temporary link files
# can be reused in rpki config
# rm -f "${DIRECTORY}"/config/_aslevel_links_*.txt
