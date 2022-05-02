#!/bin/bash

# This function runs or undo a hijack. Hijacks can be MOAS or Type-1.
# HIJACKED_AS is the hijacker AS number
# HIJACKED_PREFIX is the hijacked prefix
# SEQ is the sequence number used in the route-map (you can use e.g., 3)
# --clear indicates whether the function runs a hijack or undo a hijack
# --origin_as is used to change the origin_as, i.e., to do a Typo-1 Hijack

# This script must be executed from the platform directory.

run_hijack () {

    HIJACKER_AS=$1
    HIJACKED_PREFIX=$2
    SEQ=$3
    CLEAR=""

    if [ -z "$HIJACKER_AS" ] || [ -z "$HIJACKED_PREFIX" ] || [ -z "$SEQ" ]; then
        echo >&2 "$UTIL run-hijack: not enough arguments"
        exit 1
    fi

    shift 3
    while [ $# -ne 0 ]; do
        case $1 in
            "--origin_as")
                ORIGIN_AS=$2
                shift 
                shift
                ;;
            "--clear")
                CLEAR="no"
                shift
                ;;
            *)
                echo >&2 "$UTIL run-hijack: unknown option \"$1\""
                exit 1
                ;;
        esac
    done

    echo $HIJACKER_AS $HIJACKED_PREFIX $SEQ $ORIGIN_AS $CLEAR 

    # read configs
    readarray groups < config/AS_config.txt
    readarray extern_links < config/external_links_config.txt

    group_numbers=${#groups[@]}
    n_extern_links=${#extern_links[@]}

    route_map_permit=$((SEQ+100))

    for ((k=0;k<group_numbers;k++)); do
        group_k=(${groups[$k]})
        group_number="${group_k[0]}"
        group_as="${group_k[1]}"
        group_config="${group_k[2]}"
        group_router_config="${group_k[3]}"

        if [ "${group_number}" != "IXP" ];then

            if [ "${group_number}" == "$HIJACKER_AS" ];then

                readarray routers < config/$group_router_config
                n_routers=${#routers[@]}

                for ((i=0;i<n_routers;i++)); do
                    router_i=(${routers[$i]})
                    rname="${router_i[0]}"

                    if [ -z "$ORIGIN_AS" ]; then 

                        docker exec -it ${group_number}_${rname}router vtysh -c "conf t" -c "router bgp ${group_number}" -c "address-family ipv4 unicast" -c "$CLEAR network $HIJACKED_PREFIX"
                        docker exec -it ${group_number}_${rname}router vtysh -c "conf t" -c "$CLEAR ip prefix-list OWN_PREFIX seq $SEQ permit $HIJACKED_PREFIX"
                        docker exec -it ${group_number}_${rname}router vtysh -c "conf t" -c "$CLEAR ip route $HIJACKED_PREFIX Null0"

                    else
                        for ((j=0;j<n_extern_links;j++)); do
                            row_j=(${extern_links[$j]})
                            grp_1="${row_j[0]}"
                            router_grp_1="${row_j[1]}"
                            relation_grp_1="${row_j[2]}"
                            grp_2="${row_j[3]}"
                            router_grp_2="${row_j[4]}"
                            relation_grp_2="${row_j[5]}"
                            throughput="${row_j[6]}"
                            delay="${row_j[7]}"


                            bgp_peer_num=''
                            if [ "${grp_1}" == "${group_number}" ] && [ "${router_grp_1}" == "$rname" ] ;then
                                bgp_peer_num="${grp_2}"

                            elif [ "${grp_2}" == "${group_number}" ] && [ "${router_grp_2}" == "$rname" ] ;then
                                bgp_peer_num="${grp_1}"
                            fi

                            if [ ! -z "$bgp_peer_num" ]; then 
                                str_tmp=''

                                # Check if the router is connected to an IXP or not
                                # and computes the route map name accordingly as well as the cummunity list
                                for ((p=0;p<group_numbers;p++)); do
                                    group_p=(${groups[$p]})
                                    group_number_tmp="${group_p[0]}"
                                    group_as_tmp="${group_p[1]}"
                                    if [ "${bgp_peer_num}" = "${group_number_tmp}" ];then
                                        if [ "${group_as_tmp}" = "IXP" ];then
                                            route_map_name="IXP_OUT_"$bgp_peer_num
                                            ixp_peers="${row_j[8]}"
                                            for peer in $(echo $ixp_peers | sed "s/,/ /g"); do
                                                str_tmp=${str_tmp}${grp_2}:${peer}" "
                                            done
                                        else
                                            route_map_name="LOCAL_PREF_OUT_"$bgp_peer_num
                                        fi
                                    fi
                                done

                                # In case we execute the hijack, for the route-map.
                                if [ -z "$CLEAR" ]; then
                                    docker exec -it ${group_number}_${rname}router vtysh \
                                        -c "conf t" \
                                        -c "ip prefix-list HIJACKED_PREFIX_$ORIGIN_AS seq $SEQ permit $HIJACKED_PREFIX" \
                                        -c "route-map $route_map_name permit $route_map_permit" \
                                        -c "match ip address prefix-list HIJACKED_PREFIX_$ORIGIN_AS" \
                                        -c "set as-path prepend $ORIGIN_AS $ORIGIN_AS $ORIGIN_AS $ORIGIN_AS"
                                    
                                    # Set communities in case the peer is an IXP
                                    if [ ! -z "$str_tmp" ]; then
                                        docker exec -it ${group_number}_${rname}router vtysh \
                                            -c "conf t" \
                                            -c "route-map $route_map_name permit $route_map_permit" \
                                            -c "set community $str_tmp"
                                    fi
                                # In case we need to undo the route-map used for the hijack.
                                else

                                    docker exec -it ${group_number}_${rname}router vtysh \
                                        -c "conf t" \
                                        -c "$CLEAR ip prefix-list HIJACKED_PREFIX_$ORIGIN_AS seq $SEQ permit $HIJACKED_PREFIX" \
                                        -c "$CLEAR route-map $route_map_name permit $route_map_permit"
                                fi
                                # Execute or undo the hijack.
                                docker exec -it ${group_number}_${rname}router vtysh -c "conf t" -c "router bgp ${group_number}" -c "address-family ipv4 unicast" -c "$CLEAR network $HIJACKED_PREFIX"
                                docker exec -it ${group_number}_${rname}router vtysh -c "conf t" -c "$CLEAR ip route $HIJACKED_PREFIX Null0"
                            fi
                        done
                    fi
                done
            fi
        fi
    done
}
