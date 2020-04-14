#!/bin/bash
#
# Upload the looking glass on a web server

# REQUIREMENT: make sure to upload you public in the remote server where you
# want to upload the looking glass. And change the username when doing the scp.

set -o errexit
set -o pipefail
set -o nounset

# read configs
readarray groups < config/AS_config.txt
group_numbers=${#groups[@]}

while true
do
    # mkdir tmp
    for ((k=0;k<group_numbers;k++)); do
        group_k=(${groups[$k]})
        group_number="${group_k[0]}"
        group_as="${group_k[1]}"
        group_config="${group_k[2]}"
        group_router_config="${group_k[3]}"

        if [ "${group_as}" != "IXP" ];then

            readarray routers < config/$group_router_config
            n_routers=${#routers[@]}

            mkdir G$group_number

            for ((i=0;i<n_routers;i++)); do
                router_i=(${routers[$i]})
                rname="${router_i[0]}"
                property1="${router_i[1]}"
                property2="${router_i[2]}"

                cp groups/g${group_number}/${rname}/looking_glass.txt G$group_number/${rname}.txt

                echo $group_number $rname
            done
            scp -r G$group_number thomahol@virt07.ethz.ch:/home/web_commnet/public_html/routing_project/looking_glass/

            rm -r G$group_number
            echo $group_number done
        fi
    done
    sleep 120
done
