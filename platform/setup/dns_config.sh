#!/bin/bash
#
# generates dns config files for the dns server in groups/dns/

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"
source "${DIRECTORY}"/config/subnet_config.sh

# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt

n_groups=${#groups[@]}

# all configs are safed in groups
mkdir "${DIRECTORY}"/groups/dns
mkdir "${DIRECTORY}"/groups/dns/group_config
mkdir "${DIRECTORY}"/groups/dns/zones

location_options="${DIRECTORY}"/groups/dns/named.conf.options
echo "options {" >> "${location_options}"
echo "    directory \"/var/cache/bind\";" >> "${location_options}"
echo "" >> "${location_options}"
echo "    recursion no;" >> "${location_options}"
echo -n "    listen-on { " >> "${location_options}"

subnet_router="$(subnet_router_DNS -1 "dns")"
echo -n "${subnet_router%???}""; " >> "${location_options}"

echo "};" >> "${location_options}"
echo "    allow-transfer { none; };" >> "${location_options}"
echo "" >> "${location_options}"
echo "    dnssec-validation auto; " >> "${location_options}"
echo "    auth-nxdomain no;    # conform to RFC1035" >> "${location_options}"
echo "};" >> "${location_options}"

for ((i=0;i<n_groups;i++)); do
    group_i=(${groups[$i]})
    group_number="${group_i[0]}"
    group_as="${group_i[1]}"
    group_config="${group_i[2]}"
    group_router_config="${group_i[3]}"
    group_internal_links="${group_i[4]}"

    location_local="${DIRECTORY}"/groups/dns/named.conf.local
    location_grp="groups/dns/group_config/named.conf.local.group""${group_number}"
    if [ "${group_as}" != "IXP" ];then

        readarray routers < "${DIRECTORY}"/config/$group_router_config
        readarray intern_links < "${DIRECTORY}"/config/$group_internal_links
        n_routers=${#routers[@]}
        n_intern_links=${#intern_links[@]}

        echo "include \"/etc/bind/group_config/named.conf.local.group"${group_number}"\";" >> "${location_local}"
        echo "zone \"group"${group_number}"\" {" >> "${location_grp}"
        echo " type master;" >> "${location_grp}"
        echo " file \"/etc/bind/zones/db.group"${group_number}"\";" >> "${location_grp}"
        echo "};" >> "${location_grp}"
        echo "zone \""${group_number}".in-addr.arpa\" {" >> "${location_grp}"
        echo " type master;" >> "${location_grp}"
        echo " file \"/etc/bind/zones/db."${group_number}"\";" >> "${location_grp}"
        echo "};" >> "${location_grp}"
    fi
done

for ((j=0;j<n_groups;j++)); do
    group_j=(${groups[$j]})
    group_number="${group_j[0]}"
    group_as="${group_j[1]}"
    group_config="${group_j[2]}"
    group_router_config="${group_j[3]}"
    group_internal_links="${group_j[4]}"

    location_db="groups/dns/zones/db.""${group_number}"
    location_grp="groups/dns/zones/db.group""${group_number}"

    if [ "${group_as}" != "IXP" ];then

        readarray routers < "${DIRECTORY}"/config/$group_router_config
        readarray intern_links < "${DIRECTORY}"/config/$group_internal_links
        n_routers=${#routers[@]}
        n_intern_links=${#intern_links[@]}

        echo ";" >> "${location_db}"
        echo "; BIND reverse data file for local loopback interface" >> "${location_db}"
        echo ";" >> "${location_db}"
        echo "\$TTL    604800" >> "${location_db}"
        echo "@   IN  SOA ns.group${group_number}. ns.group${group_number}. (" >> "${location_db}"
        echo "                  ${group_number}     ; Serial" >> "${location_db}"
        echo "             604800     ; Refresh" >> "${location_db}"
        echo "              86400     ; Retry" >> "${location_db}"
        echo "            2419200     ; Expire" >> "${location_db}"
        echo "             604800 )   ; Negative Cache TTL" >> "${location_db}"
        echo ";" >> "${location_db}"
        echo "" >> "${location_db}"
        echo "    IN  NS  ns.group${group_number}." >> "${location_db}"
        echo "" >> "${location_db}"
        echo "" >> "${location_db}"

        echo ";" >> "${location_grp}"
        echo "; BIND data file for local loopback interface" >> "${location_grp}"
        echo ";" >> "${location_grp}"
        echo "\$TTL    604800" >> "${location_grp}"
        echo "@       IN      SOA     ns.group${group_number}. admin.group${group_number}. (" >> "${location_grp}"
        echo "                              ${group_number}         ; Serial" >> "${location_grp}"
        echo "                         604800         ; Refresh" >> "${location_grp}"
        echo "                          86400         ; Retry" >> "${location_grp}"
        echo "                        2419200         ; Expire" >> "${location_grp}"
        echo "                         604800 )       ; Negative Cache TTL" >> "${location_grp}"
        echo ";" >> "${location_grp}"
        echo "" >> "${location_grp}"
        echo "        IN      NS      ns.group${group_number}." >> "${location_grp}"
        echo "" >> "${location_grp}"

        subnet="$(subnet_router_DNS "${group_number}" "dns")"

        echo "ns.group""$group_number"".      IN      A       ""${subnet%???}" >> "${location_grp}"
        echo "" >> "${location_grp}"

        for ((i=0;i<n_routers;i++)); do
            router_i=(${routers[$i]})
            rname="${router_i[0]}"
            property1="${router_i[1]}"
            property2="${router_i[2]}"

            if [[ "${property2}" == host* ]];then
                subnet1="$(subnet_host_router "${group_number}" "$i" "host")"
                subnet2="$(subnet_host_router "${group_number}" "$i" "router")"

                first_sub1="${subnet1#*.}"
                first_sub2="${subnet2#*.}"

                second_sub1="${subnet1#*.*.}"
                second_sub2="${subnet2#*.*.}"

                third_sub1="${subnet1#*.*.*.}"
                third_sub2="${subnet2#*.*.*.}"

                reverse1="${third_sub1%/*}"".""${second_sub1%.*}"".""${first_sub1%.*.*}"
                reverse2="${third_sub2%/*}"".""${second_sub2%.*}"".""${first_sub2%.*.*}"

                echo "${reverse1}"" IN  PTR ""host""-""${rname}"".group""${group_number}""." >> "${location_db}"
                echo "${reverse2}"" IN  PTR ""${rname}""-""host"".group""${group_number}""." >> "${location_db}"

                echo "host""-""${rname}"".group""${group_number}"".       IN      A      " "${subnet1%/*}" >> "${location_grp}"
                echo "${rname}""-""host"".group""${group_number}"".       IN      A      " "${subnet2%/*}" >> "${location_grp}"
            fi
        done

        for ((i=0;i<n_intern_links;i++)); do
            row_i=(${intern_links[$i]})
            router1="${row_i[0]}"
            router2="${row_i[1]}"

            subnet1="$(subnet_router_router_intern "${group_number}" "$i" "1")"
            subnet2="$(subnet_router_router_intern "${group_number}" "$i" "2")"

            first_sub1="${subnet1#*.}"
            first_sub2="${subnet2#*.}"

            second_sub1="${subnet1#*.*.}"
            second_sub2="${subnet2#*.*.}"

            third_sub1="${subnet1#*.*.*.}"
            third_sub2="${subnet2#*.*.*.}"

            reverse1="${third_sub1%/*}"".""${second_sub1%.*}"".""${first_sub1%.*.*}"
            reverse2="${third_sub2%/*}"".""${second_sub2%.*}"".""${first_sub2%.*.*}"

            echo "${reverse1}"" IN  PTR ""${router1}""-""${router2}"".group""${group_number}""." >> "${location_db}"
            echo "${reverse2}"" IN  PTR ""${router2}""-""${router1}"".group""${group_number}""." >> "${location_db}"
            echo "${router1}""-""${router2}"".group""${group_number}"".       IN      A      " "${subnet1%/*}" >> "${location_grp}"
            echo "${router2}""-""${router1}"".group""${group_number}"".       IN      A      " "${subnet2%/*}" >> "${location_grp}"
        done
    fi
done
