#!/bin/bash
#
# creates group folder
# creates for every group a folder in groups
# creates for every location a folder in group folder
# initializes scripts for ovs and ip setup

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"

# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt
group_numbers=${#groups[@]}

mkdir "${DIRECTORY}"/groups

for ((k=0;k<group_numbers;k++)); do
    group_k=(${groups[$k]})
    group_number="${group_k[0]}"
    group_as="${group_k[1]}"
    group_config="${group_k[2]}"
    group_router_config="${group_k[3]}"

    mkdir "${DIRECTORY}"/groups/g"${group_number}"

    if [ "${group_as}" != "IXP" ];then

        readarray routers < "${DIRECTORY}"/config/$group_router_config
        n_routers=${#routers[@]}

        for ((i=0;i<n_routers;i++)); do
            router_i=(${routers[$i]})
            rname="${router_i[0]}"

            location="${DIRECTORY}"/groups/g"${group_number}"/"${rname}"
            mkdir "${location}"
            # router configs are safe periodically in frr.con
            touch  "${location}"/frr.conf
            cp config/daemons "${location}"/daemons
            touch  "${location}"/connectivity.txt
            touch  "${location}"/looking_glass.txt
        done
    else
        location="${DIRECTORY}"/groups/g"${group_number}"
        touch  "${location}"/frr.conf
        cp config/daemons "${location}"/daemons
    fi
done

location="${DIRECTORY}"/groups

echo "#!/bin/bash" > "${location}"/ip_setup.sh
echo "#!/bin/bash" > "${location}"/add_ports.sh
echo "#!/bin/bash" > "${location}"/add_bridges.sh
echo "#!/bin/bash" > "${location}"/l2_init_switch.sh
echo "#!/bin/bash" > "${location}"/delay_throughput.sh
echo "#!/bin/bash" > "${location}"/throughput.sh
echo "#!/bin/bash" > "${location}"/delete_veth_pairs.sh
echo "#!/bin/bash" > "${location}"/add_vpns.sh
echo "#!/bin/bash" > "${location}"/del_vpns.sh

chmod +x "${location}"/ip_setup.sh
chmod +x "${location}"/add_ports.sh
chmod +x "${location}"/add_bridges.sh
chmod +x "${location}"/l2_init_switch.sh
chmod +x "${location}"/delay_throughput.sh
chmod +x "${location}"/throughput.sh
chmod +x "${location}"/delete_veth_pairs.sh
chmod +x "${location}"/add_vpns.sh
chmod +x "${location}"/del_vpns.sh

echo -n "ovs-vsctl " >> "${location}"/add_ports.sh
echo -n "ovs-vsctl " >> "${location}"/add_bridges.sh
echo -n "ovs-vsctl " >> "${location}"/throughput.sh

echo "create_netns_link () { ">> "${location}"/ip_setup.sh
echo "  mkdir -p /var/run/netns">> "${location}"/ip_setup.sh
echo "  if [ ! -e /var/run/netns/"\$PID" ]; then">> "${location}"/ip_setup.sh
echo "    ln -s /proc/"\$PID"/ns/net /var/run/netns/"\$PID"">> "${location}"/ip_setup.sh
echo "    trap 'delete_netns_link' 0">> "${location}"/ip_setup.sh
echo "    for signal in 1 2 3 13 14 15; do">> "${location}"/ip_setup.sh
echo "      trap 'delete_netns_link; trap - \$signal; kill -\$signal \$\$' \$signal">> "${location}"/ip_setup.sh
echo "     done">> "${location}"/ip_setup.sh
echo "  fi">> "${location}"/ip_setup.sh
echo "}">> "${location}"/ip_setup.sh
echo " ">> "${location}"/ip_setup.sh
echo "delete_netns_link () {">> "${location}"/ip_setup.sh
echo "  rm -f /var/run/netns/"\$PID"">> "${location}"/ip_setup.sh
echo "}">> "${location}"/ip_setup.sh
