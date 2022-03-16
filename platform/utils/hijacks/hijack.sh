#ip prefix-list OWN_PREFIX seq 5 permit 1.0.0.0/8
#network 12.200.0.0/23
# 12 31 32 51 52 109 110

# echo docker exec -it ${asn}_BROOrouter vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.0/24"
# echo docker exec -it ${asn}_BROOrouter vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq 5 permit ${target}.108.0.0/24"

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

    for ((k=0;k<group_numbers;k++)); do
        group_k=(${groups[$k]})
        group_number="${group_k[0]}"
        group_as="${group_k[1]}"
        group_config="${group_k[2]}"
        group_router_config="${group_k[3]}"

        if [ "${group_number}" != "IXP" ];then

            if [ "${group_number}" == "$HIJACKER_AS" ];then
            echo ${group_number}

                readarray routers < config/$group_router_config
                n_routers=${#routers[@]}

                for ((i=0;i<n_routers;i++)); do
                    router_i=(${routers[$i]})
                    rname="${router_i[0]}"
                    echo $rname

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
                                # echo "1 "$grp_1 $group_number $router_grp_1 $rname $bgp_peer_num

                            elif [ "${grp_2}" == "${group_number}" ] && [ "${router_grp_2}" == "$rname" ] ;then
                                bgp_peer_num="${grp_1}"
                                # echo "2 "$grp_2 $group_number $router_grp_2 $rname $bgp_peer_num
                            fi

                            # echo $bgp_peer_num
                            if [ ! -z "$bgp_peer_num" ]; then 
                                if [ -z "$CLEAR" ]; then
                                    docker exec -it ${group_number}_${rname}router vtysh \
                                        -c "conf t" \
                                        -c "ip prefix-list HIJACKED_PREFIX seq 10 permit $HIJACKED_PREFIX" \
                                        -c "route-map LOCAL_PREF_OUT_$bgp_peer_num permit 3" \
                                        -c "match ip address prefix-list HIJACKED_PREFIX" \
                                        -c "set as-path prepend $ORIGIN_AS" 
                                else
                                    docker exec -it ${group_number}_${rname}router vtysh \
                                        -c "conf t" \
                                        -c "$CLEAR ip prefix-list HIJACKED_PREFIX seq 10 permit $HIJACKED_PREFIX" \
                                        -c "$CLEAR route-map LOCAL_PREF_OUT_$bgp_peer_num permit 3"
                                fi
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

# run_hijack 3 4.101.0.0/25 100 --origin_as 7 --clear
# seq=20
# asn=41
# for target in 3 5 7 9
# do
#     echo "AS "$asn" hijacks AS"$target

#     for r in BROO NEWY; do
#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.0/25"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.128/25"

#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $seq permit ${target}.108.0.0/25"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $(($seq+1)) permit ${target}.108.0.128/25"

#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip route ${target}.108.0.0/25 Null0"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip route ${target}.108.0.128/25 Null0"
#     done
#     seq=$(($seq+2))
# done

# seq=20
# asn=42
# for target in 4 6 8 10
# do
#     echo "AS "$asn" hijacks AS"$target

#     for r in BROO NEWY; do
#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.0/25"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.128/25"

#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $seq permit ${target}.108.0.0/25"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $(($seq+1)) permit ${target}.108.0.128/25"
  
#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip route ${target}.108.0.0/25 Null0"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip route ${target}.108.0.128/25 Null0" 
#     done
#     seq=$(($seq+2))
# done

# seq=20
# asn=61
# for target in 103 105 107 109
# do
#     echo "AS "$asn" hijacks AS"$target

#     for r in BROO NEWY; do
#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.0/25"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.128/25"

#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $seq permit ${target}.108.0.0/25"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $(($seq+1)) permit ${target}.108.0.128/25"
    
#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip route ${target}.108.0.0/25 Null0"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip route ${target}.108.0.128/25 Null0"
#     done
#     seq=$(($seq+2))
# done

# seq=20
# asn=62
# for target in 104 106 108 110
# do
#     echo "AS "$asn" hijacks AS"$target

#     for r in BROO NEWY; do
#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.0/25"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.128/25"

#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $seq permit ${target}.108.0.0/25"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $(($seq+1)) permit ${target}.108.0.128/25"
    
#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip route ${target}.108.0.0/25 Null0"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip route ${target}.108.0.128/25 Null0"
#     done
#     seq=$(($seq+2))
# done

# seq=20
# asn=81
# for target in 23 25 27 29
# do
#     echo "AS "$asn" hijacks AS"$target

#     for r in BROO NEWY; do
#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.0/25"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.128/25"

#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $seq permit ${target}.108.0.0/25"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $(($seq+1)) permit ${target}.108.0.128/25"
    
#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip route ${target}.108.0.0/25 Null0"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip route ${target}.108.0.128/25 Null0"
#     done
#     seq=$(($seq+2))
# done

# seq=20
# asn=82
# for target in 24 26 28 30
# do
#     echo "AS "$asn" hijacks AS"$target

#     for r in BROO NEWY; do
#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.0/25"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.128/25"

#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $seq permit ${target}.108.0.0/25"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $(($seq+1)) permit ${target}.108.0.128/25"
    
#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip route ${target}.108.0.0/25 Null0"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip route ${target}.108.0.128/25 Null0"
#     done
#     seq=$(($seq+2))
# done

# seq=20
# asn=102
# for target in 64 66 68 70
# do
#     echo "AS "$asn" hijacks AS"$target

#     for r in BROO NEWY; do
#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.0/25"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.128/25"

#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $seq permit ${target}.108.0.0/25"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $(($seq+1)) permit ${target}.108.0.128/25"
    
#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip route ${target}.108.0.0/25 Null0"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip route ${target}.108.0.128/25 Null0"
#     done
#     seq=$(($seq+2))
# done

# seq=20
# asn=101
# for target in 63 65 67 69
# do
#     echo "AS "$asn" hijacks AS"$target

#     for r in BROO NEWY; do
#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.0/25"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.128/25"

#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $seq permit ${target}.108.0.0/25"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $(($seq+1)) permit ${target}.108.0.128/25"
    
#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip route ${target}.108.0.0/25 Null0"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip route ${target}.108.0.128/25 Null0"
#     done
#     seq=$(($seq+2))
# done

# seq=20
# asn=2
# for target in 44 46 48 50
# do
#     echo "AS "$asn" hijacks AS"$target

#     for r in BROO NEWY; do
#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.0/25"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.128/25"

#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $seq permit ${target}.108.0.0/25"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $(($seq+1)) permit ${target}.108.0.128/25"

#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip route ${target}.108.0.0/25 Null0"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip route ${target}.108.0.128/25 Null0"    
#     done
#     seq=$(($seq+2))
# done

# seq=20
# asn=1
# for target in 43 45 47 49
# do
#     echo "AS "$asn" hijacks AS"$target

#     for r in BROO NEWY; do
#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.0/25"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.128/25"

#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $seq permit ${target}.108.0.0/25"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $(($seq+1)) permit ${target}.108.0.128/25"
    
#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip route ${target}.108.0.0/25 Null0"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip route ${target}.108.0.128/25 Null0"
#     done
#     seq=$(($seq+2))
# done

# seq=20
# asn=22
# for target in 84 86 88 90
# do
#     echo "AS "$asn" hijacks AS"$target

#     for r in BROO NEWY; do
#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.0/25"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.128/25"

#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $seq permit ${target}.108.0.0/25"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $(($seq+1)) permit ${target}.108.0.128/25"
    
#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip route ${target}.108.0.0/25 Null0"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip route ${target}.108.0.128/25 Null0"
#     done
#     seq=$(($seq+2))
# done

# seq=20
# asn=21
# for target in 83 85 87 89
# do
#     echo "AS "$asn" hijacks AS"$target

#     for r in BROO NEWY; do
#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.0/25"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.128/25"

#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $seq permit ${target}.108.0.0/25"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $(($seq+1)) permit ${target}.108.0.128/25"
    
#         docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip route ${target}.108.0.0/25 Null0"
#         # docker exec -it ${asn}_${r}router vtysh -c "conf t" -c "ip route ${target}.108.0.128/25 Null0"
#     done
#     seq=$(($seq+2))
# done
