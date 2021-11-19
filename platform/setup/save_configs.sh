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

n_groups=${#groups[@]}

for ((k=0;k<n_groups;k++)); do
    group_k=(${groups[$k]})
    group_number="${group_k[0]}"
    group_as="${group_k[1]}"
    group_config="${group_k[2]}"
    group_router_config="${group_k[3]}"
    group_internal_links="${group_k[4]}"
    group_layer2_switches="${group_k[5]}"
    group_layer2_hosts="${group_k[6]}"
    group_layer2_links="${group_k[7]}"
    file_loc="${DIRECTORY}"/groups/g"${group_number}"/save_configs.sh

    if [ "${group_as}" != "IXP" ];then

        readarray routers < "${DIRECTORY}"/config/$group_router_config
        readarray l2_switches < "${DIRECTORY}"/config/$group_layer2_switches
        readarray l2_hosts < "${DIRECTORY}"/config/$group_layer2_hosts
        readarray l2_links < "${DIRECTORY}"/config/$group_layer2_links
        n_routers=${#routers[@]}
        n_l2_switches=${#l2_switches[@]}
        n_l2_hosts=${#l2_hosts[@]}
        n_l2_links=${#l2_links[@]}

        l2_rname="-"
        echo "#!/bin/bash" > "${file_loc}"
        echo "" >> "${file_loc}"
        echo "dirname=configs_\$(date +%m-%d-%Y_%H-%M-%S)" >> "${file_loc}"
        echo "mkdir \$dirname" >> "${file_loc}"


        chmod 0755 "${file_loc}"

        declare -A l2_id
        declare -A l2_cur

        for ((i=0;i<n_routers;i++)); do
            router_i=(${routers[$i]})
            rname="${router_i[0]}"
            property1="${router_i[1]}"
            property2="${router_i[2]}"
            l2_name=$(echo $property2 | cut -f 2 -d '-')
            l2_id[$l2_name]=1000000
            l2_cur[$l2_name]=0
        done

        for ((i=0;i<n_routers;i++)); do
            router_i=(${routers[$i]})
            rname="${router_i[0]}"
            property1="${router_i[1]}"
            property2="${router_i[2]}"
            l2_name=$(echo $property2 | cut -f 2 -d '-')

            if [[ ${l2_id[$l2_name]} == 1000000 ]]; then
                l2_id[$l2_name]=$i
            fi

            #ssh to router vtysh
            echo "  subnet=""$(subnet_sshContainer_groupContainer "${group_number}" "${i}" -1  "router")" >> "${file_loc}"
            echo "  ssh -t -o "StrictHostKeyChecking=no" root@\"\${subnet%???}\" -- -c 'sh run' >> \$dirname/$rname.txt" >> "${file_loc}"
        done

        for ((l=0;l<n_l2_switches;l++)); do
            switch_l=(${l2_switches[$l]})
            l2_name="${switch_l[0]}"
            sname="${switch_l[1]}"

            echo "  subnet=""$(subnet_sshContainer_groupContainer "${group_number}" "${l2_id[$l2_name]}" "${l2_cur[$l2_name]}" "L2")" >> "${file_loc}"
            echo "  ssh -t -o "StrictHostKeyChecking=no" root@\${subnet%???} \"ovsdb-client dump\" >> \$dirname/$sname.txt" >> "${file_loc}"

            l2_cur[$l2_name]=$((${l2_cur[$l2_name]}+1))
        done
    fi

    echo "zip \${dirname}.zip \${dirname}/*" >> "${file_loc}"
done
