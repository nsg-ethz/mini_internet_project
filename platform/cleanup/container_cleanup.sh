#!/bin/bash
#
# delere all group containers(ssh, routers, hosts, switches), DNS, MEASUREMENT and MATRIX

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"
source "${DIRECTORY}"/config/subnet_config.sh

# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt
readarray routers < "${DIRECTORY}"/config/router_config.txt
readarray l2_switches < "${DIRECTORY}"/config/layer2_switches_config.txt
readarray l2_hosts < "${DIRECTORY}"/config/layer2_hosts_config.txt

group_numbers=${#groups[@]}
n_routers=${#routers[@]}
n_l2_switches=${#l2_switches[@]}
n_l2_hosts=${#l2_hosts[@]}


for ((k=0;k<group_numbers;k++)); do
  group_k=(${groups[$k]})
  group_number="${group_k[0]}"
  group_as="${group_k[1]}"

  if [ "${group_as}" != "IXP" ];then

    # kill ssh container
    docker kill "${group_number}""_ssh" &>/dev/nul || true

    for ((i=0;i<n_routers;i++)); do
      router_i=(${routers[$i]})
      rname="${router_i[0]}"
      property1="${router_i[1]}"
      property2="${router_i[2]}"

      # kill router router
      docker kill "${group_number}""_""${rname}""router" &>/dev/nul || true &

      # kill host or layer 2
      if [ "${property2}" == "host" ];then
        docker kill "${group_number}""_""${rname}""host" &>/dev/nul || true &
      elif [ "${property2}" == "L2" ];then

	# kill switches
	for ((l=0;l<n_l2_switches;l++)); do

          switch_l=(${l2_switches[$l]})
	  sname="${switch_l[0]}"
	  docker kill "${group_number}""_""${rname}""_L2_""${sname}" &>/dev/nul || true &

        done

	# kill hosts
	for ((l=0;l<n_l2_hosts;l++)); do

          host_l=(${l2_hosts[$l]})
	  hname="${host_l[0]}"
	  docker kill "${group_number}""_""${rname}""_L2_""${hname}" &>/dev/nul || true &

        done

      fi

    done

  elif [ "${group_as}" = "IXP" ];then

    #kill IXP router
    docker kill "${group_number}""_IXP" &>/dev/nul || true &

  fi

done

docker kill DNS &>/dev/nul || true &
docker kill MEASUREMENT &>/dev/nul || true &
docker kill MATRIX &>/dev/nul || true &

wait
docker system prune -f
