#!/bin/bash
#
# generates dns config files for the dns server in groups/dns/
#
# BIND: a DNS server on unix
# named.conf (inclding named.conf.* files): configuration files in BIND
# zone files: plain text files that contain mapping between domain names and IP addresses
# A: map a hostname to a 32-bit IPV4 address, e.g., example.com IN A 192.0.2.1
# AAAA: IPV6
# NS: delegate a DNS zone to use the given authoritative name server,
# e.g., example.com IN NS ns1.example.com
# SOA: basic infoormation about the domain
# PTR: reverse DNS lookups, maping an IP address to a domain name
# e.g., 1.2.0.192-in-addr.arpa. IN PTR example.com
#
# for each domain, a zone file is created and referenced in named.conf.local
# e.g., zone "example.com" { type master; file "/etc/bind/zones/db.example.com"; };
# the master/slave is used for redundancy

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"
source "${DIRECTORY}"/config/subnet_config.sh
source "${DIRECTORY}"/setup/_parallel_helper.sh

# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt

n_groups=${#groups[@]}

# all configs are safed in groups
mkdir "${DIRECTORY}"/groups/dns
mkdir "${DIRECTORY}"/groups/dns/group_config
mkdir "${DIRECTORY}"/groups/dns/zones

location_options="${DIRECTORY}"/groups/dns/named.conf.options
{
    echo "options {"
    echo "    directory \"/var/cache/bind\";"
    echo ""
    echo "    recursion no;"
    echo -n "    listen-on { "

    # listen on all group interfaces
    for ((i=0;i<n_groups;i++)); do
        group_i=(${groups[$i]})
        group_number="${group_i[0]}"
        dns_subnet="$(subnet_router_DNS "${group_number}" "dns-group")"
        echo -n "${dns_subnet%???}""; "
    done
    # also add measurement interface
    subnet_measurement="$(subnet_router_DNS -1 "dns-measurement")"
    echo -n "${subnet_measurement%???}""; "

    echo "};"
    echo "    allow-transfer { none; };"
    echo ""
    echo "    dnssec-validation auto; "
    echo "    auth-nxdomain no;    # conform to RFC1035"
    echo "};"
} >> $location_options

for ((i=0;i<n_groups;i++)); do
    (
        group_i=(${groups[$i]})
        group_number="${group_i[0]}"
        group_as="${group_i[1]}"
        group_config="${group_i[2]}"
        group_router_config="${group_i[3]}"
        group_internal_links="${group_i[4]}"

        location_local="${DIRECTORY}"/groups/dns/named.conf.local
        forward_records="groups/dns/group_config/named.conf.local.group""${group_number}"
        if [ "${group_as}" != "IXP" ];then

            readarray routers < "${DIRECTORY}"/config/$group_router_config
            readarray intern_links < "${DIRECTORY}"/config/$group_internal_links
            n_routers=${#routers[@]}
            n_intern_links=${#intern_links[@]}

            echo "include \"/etc/bind/group_config/named.conf.local.group"${group_number}"\";" >> "${location_local}"
            {
                echo "zone \"group"${group_number}"\" {"
                echo " type master;"
                echo " file \"/etc/bind/zones/db.group"${group_number}"\";"
                echo "};"
                echo "zone \""${group_number}".in-addr.arpa\" {"
                echo " type master;"
                echo " file \"/etc/bind/zones/db."${group_number}"\";"
                echo "};"
            } >> $forward_records
        fi
    )  # &  # create the dns config for each group in parallel

    #wait_if_n_tasks_are_running
done

wait


forward_entry() {
    local name="$1"
    local subnet="$2"
    echo "$name. IN A ${subnet%???}"
}

reverse_entry() {
    local name="$1"
    local subnet="$2"
    local first_sub="${subnet#*.}"
    local second_sub="${subnet#*.*.}"
    local third_sub="${subnet#*.*.*.}"
    echo "${third_sub%/*}.${second_sub%.*}.${first_sub%.*.*} IN  PTR $name."
}


for ((j=0;j<n_groups;j++)); do
    group_j=(${groups[$j]})
    group_number="${group_j[0]}"
    group_as="${group_j[1]}"
    group_config="${group_j[2]}"
    group_router_config="${group_j[3]}"
    group_internal_links="${group_j[4]}"

    domain="group${group_number}"

    # create zone definitions for both forward (db.group[number]
    # and reverse (db.[number) DNS records
    forward_records="groups/dns/zones/db.$domain"
    reverse_records="groups/dns/zones/db.${group_number}"

    if [ "${group_as}" != "IXP" ];then

        readarray routers < "${DIRECTORY}"/config/$group_router_config
        readarray intern_links < "${DIRECTORY}"/config/$group_internal_links
        n_routers=${#routers[@]}
        n_intern_links=${#intern_links[@]}

        # define SOA, NS, A records for routers and host-router interfaces
        # and PTR records for reverse DNS mapping
        {
            echo ";"
            echo "; BIND reverse data file for local loopback interface"
            echo ";"
            echo "\$TTL    604800"
            echo "@   IN  SOA ns.$domain. ns.$domain. ("
            echo "                  ${group_number}     ; Serial"
            echo "             604800     ; Refresh"
            echo "              86400     ; Retry"
            echo "            2419200     ; Expire"
            echo "             604800 )   ; Negative Cache TTL"
            echo ";"
            echo ""
            echo "    IN  NS  ns.$domain."
            echo ""
            echo ""
        } >> $reverse_records

        {
            echo ";"
            echo "; BIND data file for local loopback interface"
            echo ";"
            echo "\$TTL    604800"
            echo "@       IN      SOA     ns.$domain. admin.$domain. ("
            echo "                              ${group_number}         ; Serial"
            echo "                         604800         ; Refresh"
            echo "                          86400         ; Retry"
            echo "                        2419200         ; Expire"
            echo "                         604800 )       ; Negative Cache TTL"
            echo ";"
            echo ""
            echo "        IN      NS      ns.$domain."
            echo ""
        } >> $forward_records

        # DNS.
        subnet="$(subnet_router_DNS "${group_number}" "dns-group")"
        forward_entry "ns.group$group_number" $subnet >> $forward_records
        echo "" >> $forward_records

        # Loopback and (if exists) host.
        for ((i=0;i<n_routers;i++)); do
            router_i=(${routers[$i]})
            rname="${router_i[0],,}"  # ,, converts to lowercase
            property1="${router_i[1]}"
            property2="${router_i[2]}"
            dname=$(echo $property2 | cut -s -d ':' -f 2)
            # If there is only a single router, don't add loopback multiple
            # times; this is the case if the last column contains ALL.
            single_router=${router_i[4]:-""}

            # Loopback (if single_router is empty or i==0)
            if [[ -z "${single_router}" ]] || [[ "${i}" == "0" ]]; then
                subnet="$(subnet_router $group_number $i)"
                forward_entry "${rname}.$domain" $subnet >> $forward_records
                reverse_entry "${rname}.$domain" $subnet >> $reverse_records
            fi

            # If we have a container, i.e. host attached, add entry for it.
            if [[ ! -z "${dname}" ]];then
                subnet1="$(subnet_host_router "${group_number}" "$i" "host")"
                subnet2="$(subnet_host_router "${group_number}" "$i" "router")"

                if [[ "${property2}" == *"krill"* ]]; then
                    forward_entry "rpki-server.$domain" $subnet1 >> $forward_records
                fi
                forward_entry "host.${rname}.$domain" $subnet1 >> $forward_records
                forward_entry "${rname}.$domain" $subnet2 >> $forward_records

                reverse_entry "host.${rname}.$domain" $subnet1 >> $reverse_records
                reverse_entry "${rname}.$domain" $subnet2 >> $reverse_records
            fi
            # If the measurement service is attached here, also add entries.
            if [[ "${property1}" == "MEASUREMENT" ]]; then
                m_subnet="$(subnet_router_MEASUREMENT "${group_number}" "group")"
                forward_entry "measurement.${rname}.$domain" $m_subnet >> $forward_records
                reverse_entry "measurement.${rname}.$domain" $m_subnet >> $reverse_records
            fi
        done

        # Internal links: add an entry for every interface.
        for ((i=0;i<n_intern_links;i++)); do
            row_i=(${intern_links[$i]})
            router1="${row_i[0],,}"  # ,, converts to lowercase
            router2="${row_i[1],,}"  # ,, converts to lowercase

            subnet1="$(subnet_router_router_intern "${group_number}" "$i" "1")"
            subnet2="$(subnet_router_router_intern "${group_number}" "$i" "2")"

            reverse_entry "${router1}.$domain" $subnet1 >> $reverse_records
            reverse_entry "${router2}.$domain" $subnet2 >> $reverse_records

            forward_entry "${router1}.$domain" $subnet1 >> $forward_records
            forward_entry "${router2}.$domain" $subnet2 >> $forward_records
        done
    fi

    # Also add an entry for the MEASUREMENT interface
    # subnet="$(subnet_router_MEASUREMENT "${group_number}" "group")"
    # forward_entry "measurement.$domain" $subnet >> $forward_records
    # reverse_entry "measurement.$domain" $subnet >> $reverse_records
done
