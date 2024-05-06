#!/bin/bash
#
# creates a goto.sh script for every group ssh container

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY=$(readlink -f $1)
source "${DIRECTORY}"/config/variables.sh
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
    restore_loc="${DIRECTORY}"/groups/g"${group_number}"/restore_configs.sh
    restart_ospfd="${DIRECTORY}"/groups/g"${group_number}"/restart_ospfd.sh

    # Skip IXPS.
    if [ "${group_as}" == "IXP" ]; then continue ; fi

    readarray routers < "${DIRECTORY}"/config/$group_router_config
    readarray l2_switches < "${DIRECTORY}"/config/$group_layer2_switches
    readarray l2_hosts < "${DIRECTORY}"/config/$group_layer2_hosts
    readarray l2_links < "${DIRECTORY}"/config/$group_layer2_links
    n_routers=${#routers[@]}
    n_l2_switches=${#l2_switches[@]}
    n_l2_hosts=${#l2_hosts[@]}
    n_l2_links=${#l2_links[@]}
    l2_rname="-"

    # Prepare group files.
    # ====================
    # Save config.
    {
        echo "#!/bin/bash"
        echo ""
        echo 'dirname=configs_${1:-$(date +%m-%d-%Y_%H-%M-%S)}'
        echo "mkdir -p \$dirname"
        echo ""
        echo '# Arguments: filename, subnet, command'
        echo 'save() { eval "ssh -q -o StrictHostKeyChecking=no root@${2%???} ${@:3} > $1" ; }'
        echo ""
    } > $file_loc

    # Restore config.
    cp "${DIRECTORY}/setup/restore_configs.sh" "${restore_loc}"

    # Restart OSPFd.
    cp "${DIRECTORY}/setup/restart_ospfd.sh" "${restart_ospfd}"

    chmod 0755 $file_loc
    chmod 0755 $restore_loc
    chmod 0755 $restart_ospfd


    # Now fill them with content.
    # ===========================
    declare -A l2_id

    for ((i=0;i<n_routers;i++)); do
        router_i=(${routers[$i]})
        rname="${router_i[0]}"
        property1="${router_i[1]}"
        property2="${router_i[2]}"
        l2_name=$(echo $property2 | cut -d ':' -f 1 | cut -f 2 -d '-')
        l2_id[$l2_name]=1000000
    done

    # Routers and hosts.
    for ((i=0;i<n_routers;i++)); do
        router_i=(${routers[$i]})
        rname="${router_i[0]}"
        property1="${router_i[1]}"
        property2="${router_i[2]}"
        rcmd="${router_i[3]}"
        l2_name=$(echo $property2 | cut -d ':' -f 1 | cut -f 2 -d '-')
        subnet_router=$(subnet_sshContainer_groupContainer "${group_number}" "${i}" -1  "router")
        subnet_host=$(subnet_sshContainer_groupContainer "${group_number}" "${i}" -1  "L3-host")
        savedir="\${dirname}/$rname"

        if [[ ${l2_id[$l2_name]} == 1000000 ]]; then
            l2_id[$l2_name]=$i
        fi

        {
            if [[ $i == 0 || ${#router_i[@]} -le 4 || "${router_i[4]}" != "ALL" ]]; then
                # Router (only once if "ALL" is specified)
                echo "echo ${rname} router"
                echo "mkdir -p $savedir"
                echo "save $savedir/router.conf      $subnet_router \\\"vtysh -c \\'sh run\\'\\\""
                echo "save $savedir/router.rib.json  $subnet_router \\\"vtysh -c \\'sh ip route json\\'\\\" \\| grep -v uptime"
                if [ "${rcmd}" == "linux" ]; then
                    # If we have linux access, we may also configure tunnels, so store that output.

                    # Add tunnels and ipv6 routes.
                    echo "save $savedir/router.rib6.json $subnet_router \\\"vtysh -c \\'sh ipv6 route json\\'\\\" \\| grep -v uptime"
                    echo "save $savedir/router.tunnels   $subnet_router ip tunnel show"
                fi
            fi

            # Host
            host="host"
            if [[ ${#router_i[@]} -gt 4 && "${router_i[4]}" == "ALL" ]]; then
                host="host$i"  # Add index to host name if "ALL" is specified.
            fi
            echo "echo ${rname} $host"
            echo "save $savedir/$host.ip         $subnet_host ip addr"
            echo "save $savedir/$host.route      $subnet_host ip route"
            echo "save $savedir/$host.route6     $subnet_host ip -6 route"

            # If the host runs routinator, save routinator cache.
            htype=$(echo $property2 | cut -d ':' -f 1)
            dname=$(echo $property2 | cut -d ':' -f 2)
            if [[ ! -z "${dname}" ]]; then
                if [[ "${htype}" == *"routinator"* ]]; then
                    # echo "save $savedir/host.rpki_cache $subnet_host \"/usr/local/bin/routinator -qq update \; tar -czC /root/.rpki-cache repository\""
                    # Without update to speed up things.
                    echo "save $savedir/$host.rpki_cache $subnet_host \"tar -czC /root/.rpki-cache repository\""
                fi
            fi
        } >> $file_loc

        # Prepare restore_configs.sh and restart_osfd.sh for routers
        # TODO: include hosts.

        # TODO: Check whether this needs an update.
        # build restore_configs.sh and restart_ospfd.sh
        echo 'if [[ "$device_name" == "'"$rname"'" || $device_name == "all" ]]; then' | tee -a ${restart_ospfd} ${restore_loc} > /dev/null
        echo "  restore_router_config $subnet_router $rname $rcmd" >> ${restore_loc}
        echo "  main $subnet_router $rname $rcmd" >> ${restart_ospfd}
        echo "fi" | tee -a ${restart_ospfd} ${restore_loc} > /dev/null
    done

    {
        for ((l=0;l<n_l2_switches;l++)); do
            switch_l=(${l2_switches[$l]})
            l2_name="${switch_l[0]}"
            s_name="${switch_l[1]}"
            subnet=$(subnet_sshContainer_groupContainer "${group_number}" "${l2_id[$l2_name]}" "$l" "switch")
            savedir="\${dirname}/$s_name"

            echo "echo ${s_name}"
            echo "mkdir -p $savedir"
            echo "save $savedir/switch.db      $subnet \"ovsdb-client backup\""
            echo "save $savedir/switch.summary $subnet \"ovs-vsctl show\""
        done

        for ((l=0;l<n_l2_hosts;l++)); do
            host_l=(${l2_hosts[$l]})
            hname="${host_l[0]}"
            if [[ "$hname" != *VPN* ]];then
                l2_name="${host_l[2]}"
                subnet=$(subnet_sshContainer_groupContainer "${group_number}" "${l2_id[$l2_name]}" "$l" "L2-host")
                savedir="\${dirname}/${hname}"

                echo "echo ${hname}"
                echo "mkdir -p $savedir"
                echo "save $savedir/host.ip     $subnet \"ip addr\""
                echo "save $savedir/host.route  $subnet \"ip route\""
                echo "save $savedir/host.route6 $subnet \"ip -6 route\""
            fi
        done
    } >> $file_loc

    {
        echo ""
        echo "tar -czf \${dirname}.tar.gz \${dirname}/*"
        echo ""
        echo "echo 'Saving complete!'"
        echo "echo ''"
        echo "echo \"Download the archive file (run these commands from your own computer):\""
        echo "echo \"    scp -O -P $((2000 + ${group_number})) root@${SSH_URL}:\${dirname}.tar.gz .\""
        echo "echo 'Extract the archive:'"
        echo "echo \"    tar -xzf \${dirname}.tar.gz\""
        echo "echo \"Alternatively, to directly update the \"config\" folder in the current local directory:\""
        echo "echo \"    scp -O -r -P $((2000 + ${group_number})) root@${SSH_URL}:\${dirname} config\""
        echo "echo ''"
        echo "echo 'If the scp commands do not work for you, use ssh (also from your own computer):'"
        echo "echo '(Reliable only on UNIX systems. On Windows, you may use WinSCP instead)'"
        echo "echo \"Download the archive:\""
        echo "echo \"    ssh -q -p $((2000 + ${group_number})) root@${SSH_URL} cat \${dirname}.tar.gz > \${dirname}.tar.gz\""
        echo "echo \"Download and unpack the archive:\""
        echo "echo \"    ssh -q -p $((2000 + ${group_number})) root@${SSH_URL} cat \${dirname}.tar.gz | tar -xz\""
        echo "echo ''"
        echo "echo 'If you are using an ssh config file, you may need to update the scp and ssh commands above to match your configuration.'"
        echo "echo 'For example, you may need to replace \"root@${SSH_URL}\" with the hostname you have defined in your ssh config file.'"
        echo "echo 'Contact the TAs if you are unable to download your files!'"
    } >> $file_loc
done
