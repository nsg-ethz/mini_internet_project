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
    file_loc="${DIRECTORY}"/groups/g"${group_number}"/goto.sh

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
        echo "location=\${1,,}" >> "${file_loc}"  # ,, converts to lowercase
        echo "device=\${2:-router}" >> "${file_loc}"
        echo "device=\${device,,}" >> "${file_loc}"  # ,, converts to lowercase
        echo "" >> "${file_loc}"
        chmod 0755 "${file_loc}"

        declare -A l2_id
        declare -A l2_cur

        for ((i=0;i<n_routers;i++)); do
            router_i=(${routers[$i]})
            rname="${router_i[0],,}"  # ,, converts to lowercase
            property1="${router_i[1]}"
            property2="${router_i[2]}"
            l2_name=$(echo $property2 | cut -d ':' -f 1 | cut -f 2 -d '-')
            l2_id[$l2_name]=1000000
            l2_cur[$l2_name]=0
        done

        for ((i=0;i<n_routers;i++)); do
            router_i=(${routers[$i]})
            rname="${router_i[0],,}"  # ,, converts to lowercase
            property1="${router_i[1]}"
            property2="${router_i[2]}"
            rcmd="${router_i[3]}"
            dname=$(echo $property2 | cut -s -d ':' -f 2)
            l2_name=$(echo $property2 | cut -d ':' -f 1 | cut -f 2 -d '-')

            all_in_one="false"
            if [[ ${#router_i[@]} -gt 4 ]]; then
                if [[ "${router_i[4]}" == "ALL" ]]; then
                    all_in_one="true"
                fi
            fi

            if [[ ${l2_id[$l2_name]} == 1000000 ]]; then
                l2_id[$l2_name]=$i
            fi

            if [[ ! -z "${dname}" ]];then

                extra=""
                if [[ "$all_in_one" == "true" ]]; then
                    extra="${i}"
                fi
                # ssh to host
                echo "if [ \"\${location}\" == \"$rname\" ] && [ \"\${device}\" == \"host${extra}\" ]; then" >> "${file_loc}"
                echo "  subnet=""$(subnet_sshContainer_groupContainer "${group_number}" "${i}" -1  "L3-host")" >> "${file_loc}"
                echo "  exec ssh -t -o "StrictHostKeyChecking=no" root@\"\${subnet%???}"\" >> "${file_loc}"
                echo "fi" >> "${file_loc}"
            fi

            # If all_in_one, only add router entry the first time.
            if [[ "$all_in_one" == "true" ]] && [[ $i -gt 0 ]] ; then
                : # Do nothing.
            elif [ "${rcmd}" == "vtysh" ]; then
                #ssh to router vtysh only
                echo "if [ \"\${location}\" == \"$rname\" ] && [ \"\${device}\" == \""router"\" ]; then" >> "${file_loc}"
                echo "  subnet=""$(subnet_sshContainer_groupContainer "${group_number}" "${i}" -1  "router")" >> "${file_loc}"
                echo "  exec ssh -t -o StrictHostKeyChecking=no root@\"\${subnet%???}\" vtysh" >> "${file_loc}"
                echo "fi" >> "${file_loc}"
            else
                #ssh to router vtysh
                echo "if [ \"\${location}\" == \"$rname\" ] && [ \"\${device}\" == \""router"\" ]; then" >> "${file_loc}"
                echo "  subnet=""$(subnet_sshContainer_groupContainer "${group_number}" "${i}" -1  "router")" >> "${file_loc}"
                echo "  exec ssh -t -o StrictHostKeyChecking=no root@\"\${subnet%???}\" vtysh" >> "${file_loc}"
                echo "fi" >> "${file_loc}"

                #shh to router container
                echo "if [ \"\${location}\" == \"$rname\" ] && [ \"\${device}\" == \""container"\" ]; then" >> "${file_loc}"
                echo "  subnet=""$(subnet_sshContainer_groupContainer "${group_number}" "${i}" -1  "router")" >> "${file_loc}"
                echo "  exec ssh -t -o StrictHostKeyChecking=no root@\"\${subnet%???}\" bash" >> "${file_loc}"
                echo "fi" >> "${file_loc}"
            fi

        done

        last_l2name_s=''
        last_sname_s=''
        for ((l=0;l<n_l2_switches;l++)); do
            switch_l=(${l2_switches[$l]})
            l2_name="${switch_l[0]}"
            l2_lower="${l2_name,,}"  # ,, converts to lowercase
            sname="${switch_l[1],,}"

            echo "if [ \"\${location}\" == \"$l2_lower\" ] && [ \"\${device}\" == \""${sname}"\" ]; then" >> "${file_loc}"
            echo "  subnet=""$(subnet_sshContainer_groupContainer "${group_number}" -1 "${l}" "switch")" >> "${file_loc}"
            echo "  exec ssh -t -o StrictHostKeyChecking=no root@\"\${subnet%???}"\" >> "${file_loc}"
            echo "fi" >> "${file_loc}"

            l2_cur[$l2_name]=$((${l2_cur[$l2_name]}+1))
            last_l2name_s=$l2_name
            last_sname_s=$sname
        done

        last_l2name_h=''
        last_hname=''
        for ((l=0;l<n_l2_hosts;l++)); do
            host_l=(${l2_hosts[$l]})
            hname="${host_l[0],,}"  # ,, converts to lowercase

            if [[ "$hname" != *vpn* ]];then
                l2_name="${host_l[2]}"
                l2_lower="${l2_name,,}"  # ,, converts to lowercase

                echo "if [ \"\${location}\" == \"$l2_lower\" ] && [ \"\${device}\" == \""$hname"\" ]; then" >> "${file_loc}"
                echo "  subnet=""$(subnet_sshContainer_groupContainer "${group_number}" -1 "${l}" "L2-host")" >> "${file_loc}"
                echo "  exec ssh -t -o StrictHostKeyChecking=no root@\"\${subnet%???}"\" >> "${file_loc}"
                echo "fi" >> "${file_loc}"

                l2_cur[$l2_name]=$((${l2_cur[$l2_name]}+1))
                last_l2name_h=$l2_name
                last_hname=$hname
            fi

        done

        # Add a link to go to the measurement container
        # Note: the && device == router may seem weird, but we need to keep
        # the same format for the autocompletion to work; essentially this just
        # means that device needs to be the default value.
        echo "if [ \"\${location}\" == \"measurement\" ] && [ \"\${device}\" == \""router"\" ]; then" >> "${file_loc}"
        echo "  subnet=""$(subnet_sshContainer_groupContainer "${group_number}" -1 -1 "MEASUREMENT")" >> "${file_loc}"
        echo "  exec ssh -t -o StrictHostKeyChecking=no root@\"\${subnet%???}"\" >> "${file_loc}"
        echo "fi" >> "${file_loc}"


        echo "echo \"invalid arguments\"" >> "${file_loc}"
        echo "echo \"valid examples:\"" >> "${file_loc}"
        echo "echo \"./goto.sh $rname\"" >> "${file_loc}"
        echo "echo \"./goto.sh $rname router\"" >> "${file_loc}"
        echo "echo \"./goto.sh $rname host\"" >> "${file_loc}"

        if [ "${last_l2name_s}" != "" ];then
            echo "echo \"./goto.sh ${last_l2name_s} ${last_sname_s}\"" >> "${file_loc}"
            echo "echo \"./goto.sh ${last_l2name_h} ${last_hname}\"" >> "${file_loc}"
        fi

        echo "echo \"./goto.sh measurement\"" >> "${file_loc}"
    fi
done
