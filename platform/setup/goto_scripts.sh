#!/bin/bash
#
# creates a goto.sh script for every group ssh container

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

n_groups=${#groups[@]}
n_routers=${#routers[@]}
n_l2_switches=${#l2_switches[@]}
n_l2_hosts=${#l2_hosts[@]}

for ((k=0;k<n_groups;k++)); do
  group_k=(${groups[$k]})
  group_number="${group_k[0]}"
  group_as="${group_k[1]}"
  
  file_loc="${DIRECTORY}"/groups/g"${group_number}"/goto.sh
  
  if [ "${group_as}" != "IXP" ];then
    l2_rname="-"
    echo "#!/bin/bash" > "${file_loc}"
    echo "location=\$1" >> "${file_loc}"
    echo "device=\$2" >> "${file_loc}"
    echo "" >> "${file_loc}"
    chmod 0755 "${file_loc}"
    
    for ((i=0;i<n_routers;i++)); do
      router_i=(${routers[$i]})
      rname="${router_i[0]}"
      property1="${router_i[1]}"
      property2="${router_i[2]}"
      
      if [ "${property2}" == "host" ];then
        # ssh to host
	echo "if [ \"\${location}\" == \"$rname\" ] && [ \"\${device}\" == \""host"\" ]; then" >> "${file_loc}"
	echo "	subnet=""$(subnet_sshContainer_groupContainer "${group_number}" "${i}" -1  "host")" >> "${file_loc}"
	echo "	ssh -t -o "StrictHostKeyChecking=no" root@\"\${subnet%???}"\" >> "${file_loc}"
	echo "	exit" >> "${file_loc}"
	echo "fi" >> "${file_loc}"
      elif [ "${property2}" == "L2" ];then
        l2_rname="$rname"
	for ((l=0;l<n_l2_hosts;l++)); do
          host_l=(${l2_hosts[$l]})
	  hname="${host_l[0]}"
	  sname="${host_l[1]}"
	  echo "if [ \"\${location}\" == \"$rname\" ] && [ \"\${device}\" == \""${hname}"\" ]; then" >> "${file_loc}"
	  echo "  subnet=""$(subnet_sshContainer_groupContainer "${group_number}" "${i}" "$((${l}+${n_l2_switches}+2))" "L2")" >> "${file_loc}"
	  echo "  ssh -t -o "StrictHostKeyChecking=no" root@\"\${subnet%???}"\" >> "${file_loc}"
	  echo "  exit" >> "${file_loc}"
	  echo "fi" >> "${file_loc}"
        done
	
	for ((l=0;l<n_l2_switches;l++)); do
          switch_l=(${l2_switches[$l]})
	  sname="${switch_l[0]}"
	  echo "if [ \"\${location}\" == \"$rname\" ] && [ \"\${device}\" == \""${sname}"\" ]; then" >> "${file_loc}"
	  echo "  subnet=""$(subnet_sshContainer_groupContainer "${group_number}" "${i}" "$((${l}+2))" "L2")" >> "${file_loc}"
	  echo "  ssh -t -o "StrictHostKeyChecking=no" root@\"\${subnet%???}"\" >> "${file_loc}"
	  echo "  exit" >> "${file_loc}"
	  echo "fi" >> "${file_loc}"
        done
      fi
      
      #ssh to router vtysh
      echo "if [ \"\${location}\" == \"$rname\" ] && [ \"\${device}\" == \""router"\" ]; then" >> "${file_loc}"
      echo "  subnet=""$(subnet_sshContainer_groupContainer "${group_number}" "${i}" -1  "router")" >> "${file_loc}"
      echo "  ssh -t -o "StrictHostKeyChecking=no" root@\"\${subnet%???}\" vtysh" >> "${file_loc}" >> "${file_loc}"
      echo "  exit" >> "${file_loc}"
      echo "fi" >> "${file_loc}"
      
      #shh to router container
      echo "if [ \"\${location}\" == \"$rname\" ] && [ \"\${device}\" == \""container"\" ]; then" >> "${file_loc}"
      echo "  subnet=""$(subnet_sshContainer_groupContainer "${group_number}" "${i}" -1  "router")" >> "${file_loc}"
      echo "  ssh -t -o "StrictHostKeyChecking=no" root@\"\${subnet%???}\"" >> "${file_loc}" >> "${file_loc}"
      echo "  exit" >> "${file_loc}"
      echo "fi" >> "${file_loc}"	
    done
    
    echo "echo \"invalid arguments\"" >> "${file_loc}"
    echo "echo \"valid examples:\"" >> "${file_loc}"
    echo "echo \"./goto $rname router\"" >> "${file_loc}"
    echo "echo \"./goto $rname host\"" >> "${file_loc}"
    
    if [ "${l2_rname}" != "-" ];then
      echo "echo \"./goto ${l2_rname} ${sname}\"" >> "${file_loc}"
      echo "echo \"./goto ${l2_rname} ${hname}\"" >> "${file_loc}"
    fi
  fi	
done
