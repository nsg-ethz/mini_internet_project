#!/bin/bash

# creates ping_all_groups.sh for every host location
# the script is mounted in the container, students could change it
# for this reason it is generated every time the connectivity is tested


set -o errexit
set -o pipefail
set -o nounset

#read command
if [ $# -ne 1 ]; then
    echo $0: usage sudo ./create_ping_scripts directory
    exit 1
fi

DIRECTORY="$1"

source config/subnet_config.sh

# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt
readarray extern_links < "${DIRECTORY}"/config/external_links_config.txt
n_groups=${#groups[@]}
n_extern_links=${#extern_links[@]}

echo '' > "${DIRECTORY}"/groups/matrix/ping_all_groups.sh
echo  "#!/bin/bash" &> "${DIRECTORY}"/groups/matrix/ping_all_groups.sh
chmod +x "${DIRECTORY}"/groups/matrix/ping_all_groups.sh
echo "declare -A results" >> "${DIRECTORY}"/groups/matrix/ping_all_groups.sh
echo "echo \"\"> /home/log_ping.txt" >> "${DIRECTORY}"/groups/matrix/ping_all_groups.sh

for ((kk=0;kk<n_groups;kk++)); do
    group_kk=(${groups[$kk]})
    group_number_kk="${group_kk[0]}"
    group_as_kk="${group_kk[1]}"
    group_config="${group_kk[2]}"
    group_router_config="${group_kk[3]}"
    group_internal_links="${group_kk[4]}"

    readarray routers < "${DIRECTORY}"/config/$group_router_config
    readarray intern_links < "${DIRECTORY}"/config/$group_internal_links
    n_routers=${#routers[@]}
    n_intern_links=${#intern_links[@]}

    # find the ID of that router
    for i in "${!routers[@]}"; do
       if [[ "${routers[$i]}" == *'MATRIX_TARGET'* ]]; then
           dest_router_id=$i;
       fi
    done

    echo "echo Group "$group_kk >> "${DIRECTORY}"/groups/matrix/ping_all_groups.sh

    if [ "${group_as_kk}" != "IXP" ];then
        for ((jj=0;jj<n_groups;jj++)); do
            group_jj=(${groups[$jj]})
            group_number_jj="${group_jj[0]}"
            group_as_jj="${group_jj[1]}"

            if [ "${group_as_jj}" != "IXP" ];then
                subnet="$(subnet_host_router "${group_number_jj}" "$dest_router_id" host)"

                if [ $group_number_kk -lt 10 ];then
                    mac_addr="aa:11:11:11:11:0"$group_number_kk
                else
                    mac_addr="aa:11:11:11:11:"$group_number_kk
                fi
                cmd="nping --dest-ip "${subnet%/*}" --dest-mac "$mac_addr" --interface group_"$group_number_kk" --tcp -c 1 | grep RCVD | grep -v unreachable"
                echo "(timeout 2 "$cmd" &>> /home/log_ping.txt ) &" >> "${DIRECTORY}"/groups/matrix/ping_all_groups.sh

                echo "results[\"${group_number_kk},${group_number_jj}\"]=\$!" >> "${DIRECTORY}"/groups/matrix/ping_all_groups.sh
            fi
        done
    fi

    echo "sleep 1.5" >> "${DIRECTORY}"/groups/matrix/ping_all_groups.sh
done



echo "echo '' > /home/connectivity.txt" >> "${DIRECTORY}"/groups/matrix/ping_all_groups.sh

for ((kk=0;kk<n_groups;kk++)); do
    group_kk=(${groups[$kk]})
    group_number_kk="${group_kk[0]}"
    group_as_kk="${group_kk[1]}"
    group_router_config="${group_kk[3]}"
    group_internal_links="${group_kk[4]}"

    readarray routers < "${DIRECTORY}"/config/$group_router_config
    readarray intern_links < "${DIRECTORY}"/config/$group_internal_links
    n_routers=${#routers[@]}
    n_intern_links=${#intern_links[@]}

    if [ "${group_as_kk}" != "IXP" ];then

        for ((jj=0;jj<n_groups;jj++)); do
            group_jj=(${groups[$jj]})
            group_number_jj="${group_jj[0]}"
            group_as_jj="${group_jj[1]}"

            if [ "${group_as_jj}" != "IXP" ];then
                echo "if wait \${results[\"${group_number_kk},${group_number_jj}\"]}; then" >> "${DIRECTORY}"/groups/matrix/ping_all_groups.sh
                echo "printf \"1 \" >> /home/connectivity.txt" >> "${DIRECTORY}"/groups/matrix/ping_all_groups.sh
                echo "else" >> "${DIRECTORY}"/groups/matrix/ping_all_groups.sh
                echo "printf \"0 \" >> /home/connectivity.txt" >> "${DIRECTORY}"/groups/matrix/ping_all_groups.sh
                echo "fi" >> "${DIRECTORY}"/groups/matrix/ping_all_groups.sh
            fi
        done
        echo "printf \"\n\" >> /home/connectivity.txt" >> "${DIRECTORY}"/groups/matrix/ping_all_groups.sh
    fi
done

echo "date \"+%FT%T\">>/home/connectivity.txt" >> "${DIRECTORY}"/groups/matrix/ping_all_groups.sh

echo "cp /home/connectivity.txt /home/matrix.txt" >> "${DIRECTORY}"/groups/matrix/ping_all_groups.sh
