#!/bin/bash

# configures the IRRd database with the required objects

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"

source "${DIRECTORY}"/config/subnet_config.sh
source "${DIRECTORY}"/setup/_parallel_helper.sh
source "${DIRECTORY}"/setup/ovs-docker.sh

# Check if IRRd is used
if grep -q "irrd" "${DIRECTORY}"/config/AS_config.txt; then
    # read configs
    readarray groups < "${DIRECTORY}"/config/AS_config.txt
    readarray extern_links < "${DIRECTORY}"/config/aslevel_links.txt

    group_numbers=${#groups[@]}
    n_extern_links=${#extern_links[@]}

    # create a default password for the TA Team
    passwd=$(openssl rand -hex 8)
    echo "IRRd TA Team password: ${passwd}" > "${DIRECTORY}"/groups/irrd-ta-password.txt

    # hash the default password
    salt=$(openssl rand -hex 4)
    hashed_pw=$(openssl passwd -1 -salt "${salt}" "${passwd}")

    # read the override password
    override_password=$(cat "${DIRECTORY}"/groups/irrd_override_password.txt)

    # Set up a default maintainer and related person account for the TA-team
    echo "{" > "${DIRECTORY}"/groups/irrd_config.json
    echo "\"objects\": [ " >> "${DIRECTORY}"/groups/irrd_config.json
    echo "{\"object_text\": \"person: ComNet TA Team\\nnic-hdl: TA-TEAM\\naddress: ETH Zurich\\nphone: xxx\\ne-mail: comnet@comm-net.ethz.ch\\nsource: AUTHDATABASE\\nmnt-by: MAINT-TA-TEAM\"}," >> "${DIRECTORY}"/groups/irrd_config.json
    echo "{\"object_text\": \"mntner: MAINT-TA-TEAM\\ndescr: TA Team for the\\ndescr: ComNet Lecture\\nadmin-c: TA-TEAM\\ntech-c: TA-TEAM\\nupd-to: comnet@comm-net.ethz.ch\\nmnt-nfy: comnet@comm-net.ethz.ch\\nauth: MD5-PW ${hashed_pw}\\nnotify: comnet@comm-net.ethz.ch\\nchanged: comnet@comm-net.ethz.ch 20221018\\nsource: AUTHDATABASE\\nmnt-by:MAINT-TA-TEAM\"}" >> "${DIRECTORY}"/groups/irrd_config.json

    for ((k=0;k<group_numbers;k++)); do
        group_k=(${groups[$k]})
        group_number="${group_k[0]}"
        group_as="${group_k[1]}"
        group_config="${group_k[2]}"
        group_router_config="${group_k[3]}"
        group_internal_links="${group_k[4]}"

        AS_CUSTOMERS=""

        # Get the password and create the salt for the group
        passwd=$(awk "\$1 == \"${group_number}\" { print \$0 }" "${DIRECTORY}/groups/passwords.txt" | cut -f 2 -d ' ')
        salt=$(openssl rand -hex 4)

        # hash the password
        hashed_passwd=$(openssl passwd -1 -salt "${salt}" "${passwd}")

        # for each group, create a default maintainer and person object which can be used to modify data
        echo ",{\"object_text\": \"person: Group ${group_number}\\nnic-hdl: GROUP-${group_number}\\naddress: ETH Zurich\\nphone: xxx\\ne-mail: comnet@comm-net.ethz.ch\\nsource: AUTHDATABASE\\nmnt-by: MAINT-GROUP-${group_number}\"}," >> "${DIRECTORY}"/groups/irrd_config.json
        echo "{\"object_text\": \"mntner: MAINT-GROUP-${group_number}\\ndescr: Group ${group_number}\\nadmin-c: GROUP-${group_number}\\ntech-c: GROUP-${group_number}\\nupd-to: comnet@comm-net.ethz.ch\\nmnt-nfy: comnet@comm-net.ethz.ch\\nauth: MD5-PW ${hashed_passwd}\\nnotify: comnet@comm-net.ethz.ch\\nchanged: comnet@comm-net.ethz.ch 20221018\\nsource: AUTHDATABASE\\nmnt-by: MAINT-GROUP-${group_number}\"}" >> "${DIRECTORY}"/groups/irrd_config.json

	# Check if the network should be configured (no IXP and not preconfigured)
        if [ "${group_as}" != "IXP" ]; then
            if [ "${group_config}" == "Config" ]; then
                # Create a default route object
                echo ",{\"object_text\": \"route: ${group_number}.0.0.0/8\\norigin: AS${group_number}\\nmnt-by: MAINT-GROUP-${group_number}\\nmnt-by: MAINT-TA-TEAM\\nsource: AUTHDATABASE\"}" >> "${DIRECTORY}"/groups/irrd_config.json

                # Set up the aut-num routing information in IRRD
                echo -n ",{\"object_text\": \"aut-num: AS${group_number}\\nas-name: GROUP-${group_number}\\nmnt-by: MAINT-GROUP-${group_number}\\nmnt-by: MAINT-TA-TEAM\\nadmin-c: GROUP-${group_number}\\ntech-c: GROUP-${group_number}\\nsource: AUTHDATABASE" >> "${DIRECTORY}"/groups/irrd_config.json

		# Check the external links for all connected AS
                for ((i=0; i<n_extern_links; i++)); do
                    # Read in each line
                    row_i=(${extern_links[$i]})
                    grp_1="${row_i[0]}"
                    router_grp_1="${row_i[1]}"
                    relation_grp_1="${row_i[2]}"
                    grp_2="${row_i[3]}"
                    router_grp_2="${row_i[4]}"
                    relation_grp_2="${row_i[5]}"
                    throughput="${row_i[6]}"
                    delay="${row_i[7]}"

                    if [ "${grp_1}" == "${group_number}" ]; then
                        if [ "${relation_grp_1}" == "Provider" ]; then
                            echo -n "\\nimport: from AS${grp_2} action: local-preference = 100; accept ANY\nexport: to AS${grp_2} announce ANY" >> "${DIRECTORY}"/groups/irrd_config.json
                            AS_CUSTOMERS="AS${grp_2} ${AS_CUSTOMERS}"
                        elif [ "${relation_grp_1}" == "Customer" ]; then
                            echo -n "\\nimport: from AS${grp_2} action: local-preference = 20; accept ANY\nexport: to AS${grp_2} announce AS${group_number}:AS-CUSTOMERS" >> "${DIRECTORY}"/groups/irrd_config.json
                        elif [ "${relation_grp_1}" == "Peer" ]; then
                            # Check if either group is an IXP
                            for ((l=0;l<group_numbers;l++)); do
                                 group_l=(${groups[$l]})
                                 group_l_number=${group_l[0]}
                                 group_as="${group_l[1]}"

                                 if [ "${group_l_number}" = "${group_number}" ];then
                                      group_as_1="${group_as}"
                                 elif [ "${group_l_number}" = "${grp_2}" ];then
                                      group_as_2="${group_as}"
                                 fi
                            done

			    # In case one is IXP, add data for each (via IXP) connected AS
                            if [ "${group_as_1}" = "IXP" ] || [ "${group_as_2}" = "IXP" ]; then
                                ixp_peers="${row_i[8]}"
                                for peer in $(echo $ixp_peers | sed "s/,/ /g"); do
                                    if [ ! "${peer}" == "${group_number}" ]; then
                                        echo -n "\\nimport: from AS${peer} via IXP${grp_2} action: local-preference = 50; accept ANY\nexport: to AS${peer} announce AS${group_number}:AS-CUSTOMERS" >> "${DIRECTORY}"/groups/irrd_config.json
                                    fi
                                done
                            else
                                echo -n "\\nimport: from AS${grp_2} action: local-preference = 50; accept ANY\nexport: to AS${grp_2} announce AS${group_number}:AS-CUSTOMERS" >> "${DIRECTORY}"/groups/irrd_config.json
                            fi
                        fi
		    elif [ "${grp_2}" == "${group_number}" ]; then
                        if [ "${relation_grp_2}" == "Provider" ]; then
                            echo -n "\\nimport: from AS${grp_1} action: local-preference = 100; accept ANY\nexport: to AS${grp_1} announce ANY" >> "${DIRECTORY}"/groups/irrd_config.json
                            AS_CUSTOMERS="AS${grp_1} ${AS_CUSTOMERS}"
                        elif [ "${relation_grp_2}" == "Customer" ]; then
                            echo -n "\\nimport: from AS${grp_1} action: local-preference = 20; accept ANY\nexport: to AS${grp_1} announce AS${group_number}:AS-CUSTOMERS" >> "${DIRECTORY}"/groups/irrd_config.json
                        elif [ "${relation_grp_2}" == "Peer" ]; then
                            # Check if either group is an IXP
                            for ((l=0;l<group_numbers;l++)); do
                                 group_l=(${groups[$l]})
                                 group_l_number=${group_l[0]}
                                 group_as="${group_l[1]}"

                                 if [ "${group_l_number}" = "${group_number}" ];then
                                      group_as_1="${group_as}"
                                 elif [ "${group_l_number}" = "${grp_1}" ];then
                                      group_as_2="${group_as}"
                                 fi
                            done

			    # In case one is IXP, add data for each (via IXP) connected AS
                            if [ "${group_as_1}" = "IXP" ] || [ "${group_as_2}" = "IXP" ]; then
                                ixp_peers="${row_i[8]}"
                                for peer in $(echo $ixp_peers | sed "s/,/ /g"); do
                                    echo -n "\\nimport: from AS${peer} action: local-preference = 50; accept ANY\nexport: to AS${peer} announce AS${group_number}:AS-CUSTOMERS" >> "${DIRECTORY}"/groups/irrd_config.json
                                done
                            else
                                echo -n "\\nimport: from AS${grp_1} action: local-preference = 50; accept ANY\nexport: to AS${grp_2} announce AS${group_number}:AS-CUSTOMERS" >> "${DIRECTORY}"/groups/irrd_config.json
                            fi
                        fi
		    fi

                done
                echo "\"}" >> "${DIRECTORY}"/groups/irrd_config.json

                # Create the AS-CUSTOMER as-set in IRRd
                echo -n ",{\"object_text\": \"as-set: AS${group_number}:AS-CUSTOMERS\\nmnt-by: MAINT-GROUP-${group_number}\\nmnt-by: MAINT-TA-TEAM\\nsource: AUTHDATABASE\\nmembers: AS${group_number}" >> "${DIRECTORY}"/groups/irrd_config.json
                for customer in ${AS_CUSTOMERS}; do
                    echo -n ", ${customer}, ${customer}:AS-CUSTOMERS" >> "${DIRECTORY}"/groups/irrd_config.json
                done
                echo "\"}" >> "${DIRECTORY}"/groups/irrd_config.json
	    fi
        fi
    done

    # Set the override password
    echo "], \"override\": \"${override_password}\"}" >> ${DIRECTORY}/groups/irrd_config.json

    docker cp ${DIRECTORY}/groups/irrd_config.json 2_BASEhost:/root/irrd_config.json
    response=$(docker exec -t 2_BASEhost curl --write-out '%{http_code}' --silent --output /dev/null -X POST -H "Content-Type: application/json" -d @/root/irrd_config.json http://host-ZURI.group2/v1/submit/)

    # Check if the HTTP request was successful
    if [[ $response -eq 200 ]]; then
        echo "Default IRRd data was successfully transferred into the database"
    else
        echo -e "ERROR: The default IRRd data was not successfully transferred into the database.\nYou can find the file with the configurations under groups/irrd_config.json.\nYou can try to manually POST this from a host within the mini-internet with a similar command:\ncurl -X POST -H "Content-Type: application/json" -d @/root/irrd_config.json http://host-ZURI.group2/v1/submit/"
    fi

    # Create network setup for the webserver
    webserver_irrd_ip="$(subnet_irrd "web" "webserver")"
    irrd_webserver_ip="$(subnet_irrd "web" "irrd")"

    ip link add irrd_webserver type veth peer name webserver_irrd

    PID=$(docker inspect -f '{{.State.Pid}}' 2_ZURIhost)
    create_netns_link
    ip link set netns $PID dev irrd_webserver
    ip netns exec $PID ip a add "${irrd_webserver_ip}" dev irrd_webserver
    ip netns exec $PID ip link set dev irrd_webserver up

    PID=$(docker inspect -f '{{.State.Pid}}' WEB)
    create_netns_link
    ip link set netns $PID dev webserver_irrd
    ip netns exec $PID ip a add "${webserver_irrd_ip}" dev webserver_irrd
    ip netns exec $PID ip link set dev webserver_irrd up
fi
