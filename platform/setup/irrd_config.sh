#!/bin/bash

# configures the IRRd database with the required objects

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"

source "${DIRECTORY}"/config/subnet_config.sh
source "${DIRECTORY}"/setup/_parallel_helper.sh

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

	# TODO if necessary: Enter route objects for reserved IP prefixes

	for ((k=0;k<group_numbers;k++)); do
	    group_k=(${groups[$k]})
	    group_number="${group_k[0]}"
	    group_as="${group_k[1]}"
	    group_config="${group_k[2]}"
	    group_router_config="${group_k[3]}"
	    group_internal_links="${group_k[4]}"

	    # Get the password and create the salt for the group
	    passwd=$(awk "\$1 == \"${group_number}\" { print \$0 }" "${DIRECTORY}/groups/passwords.txt" | cut -f 2 -d ' ')
	    salt=$(openssl rand -hex 4)

	    # hash the password
	    hashed_passwd=$(openssl passwd -1 -salt "${salt}" "${passwd}")

	    # for each group, create a default maintainer and person object which can be used to modify data
	    echo "," >> "${DIRECTORY}"/groups/irrd_config.json
	    echo "{\"object_text\": \"person: Group ${group_number}\\nnic-hdl: GROUP-${group_number}\\naddress: ETH Zurich\\nphone: xxx\\ne-mail: comnet@comm-net.ethz.ch\\nsource: AUTHDATABASE\\nmnt-by: MAINT-GROUP-${group_number}\"}," >> "${DIRECTORY}"/groups/irrd_config.json
	    echo "{\"object_text\": \"mntner: MAINT-GROUP-${group_number}\\ndescr: Group ${group_number}\\nadmin-c: GROUP-${group_number}\\ntech-c: GROUP-${group_number}\\nupd-to: comnet@comm-net.ethz.ch\\nmnt-nfy: comnet@comm-net.ethz.ch\\nauth: MD5-PW ${hashed_passwd}\\nnotify: comnet@comm-net.ethz.ch\\nchanged: comnet@comm-net.ethz.ch 20221018\\nsource: AUTHDATABASE\\nmnt-by: MAINT-GROUP-${group_number}\"}" >> "${DIRECTORY}"/groups/irrd_config.json

	    # If the network is configured, create a default route object
	    if [ "${group_as}" != "IXP" ]; then
		if [ "${group_config}" == "Config" ]; then
		    echo "," >> "${DIRECTORY}"/groups/irrd_config.json
		    echo "{\"object_text\": \"route: ${group_number}.0.0.0/8\\norigin: AS${group_number}\\nmnt-by: MAINT-GROUP-${group_number}\\nmnt-by: MAINT-TA-TEAM\\nsource: AUTHDATABASE\"}" >> "${DIRECTORY}"/groups/irrd_config.json
		fi
	    fi



	    # Create routing information in IRRD
#	    if [ "${group_config}" == "Config" ]; then
#                 echo ",{\"object_text\": \"aut_num: AS${group_number}\\nas-name: GROUP-${group_number}\\nmnt-by: MAINT-GROUP-${group_number}\\nadmin-c: GROUP-${group_number}\\ntech-c: GROUP-${group_number}" >> "${DIRECTORY}"/groups/irrd_config.json
#		 for ((i=0; i<n_extern_links; i++)); do
#                     row_i=(${extern_links[$i]})
#                     grp_1="${row_i[0]}"
#                     router_grp_1="${row_i[1]}"
#                     relation_grp_1="${row_i[2]}"
#                     grp_2="${row_i[3]}"
#                     router_grp_2="${row_i[4]}"
#                     relation_grp_2="${row_i[5]}"
#                     throughput="${row_i[6]}"
#                     delay="${row_i[7]}"
#		 done
#		 echo "\"" >> "${DIRECTORY}"/groups/irrd_config.json
#	    fi
	done

	# Set the override password
	echo "], \"override\": \"${override_password}\"}" >> ${DIRECTORY}/groups/irrd_config.json

	docker cp ${DIRECTORY}/groups/irrd_config.json 2_BASEhost:/root/irrd_config.json
	response=$(docker exec -t 2_BASEhost curl --write-out '%{http_code}' --silent --output /dev/null -X POST -H "Content-Type: application/json" -d @/root/irrd_config.json http://host-ZURI.group2:8080/v1/submit/)

	# Check if the HTTP request was successful
	if [[ $response -eq 200 ]]; then
    	echo "Default IRRd data was successfully transferred into the database"
	else
	    echo -e "ERROR: The default IRRd data was not successfully transferred into the database.\nYou can find the file with the configurations under groups/irrd_config.json.\nYou can try to manually POST this from a host within the mini-internet with a similar command:\ncurl -X POST -H "Content-Type: application/json" -d @/root/irrd_config.json http://host-ZURI.group2:8080/v1/submit/"

	fi
fi
