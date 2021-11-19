#ip prefix-list OWN_PREFIX seq 5 permit 1.0.0.0/8
#network 12.200.0.0/23
# 12 31 32 51 52 109 110

# echo docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.0/24"
# echo docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq 5 permit ${target}.108.0.0/24"

seq=20
asn=41
for target in 3 5 7 9 11
do
    echo "AS "$asn" hijacks AS"$target

    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.0/25"
    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.128/25"

    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $seq permit ${target}.108.0.0/25"
    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $(($seq+1)) permit ${target}.108.0.128/25"
    seq=$(($seq+2))
done

seq=20
asn=42
for target in 4 6 8 10 12
do
    echo "AS "$asn" hijacks AS"$target

    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.0/25"
    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.128/25"

    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $seq permit ${target}.108.0.0/25"
    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $(($seq+1)) permit ${target}.108.0.128/25"
    seq=$(($seq+2))
done

seq=20
asn=61
for target in 103 105 107 109
do
    echo "AS "$asn" hijacks AS"$target

    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.0/25"
    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.128/25"

    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $seq permit ${target}.108.0.0/25"
    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $(($seq+1)) permit ${target}.108.0.128/25"
    seq=$(($seq+2))
done

seq=20
asn=62
for target in 104 106 108 110
do
    echo "AS "$asn" hijacks AS"$target

    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.0/25"
    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.128/25"

    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $seq permit ${target}.108.0.0/25"
    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $(($seq+1)) permit ${target}.108.0.128/25"
    seq=$(($seq+2))
done

seq=20
asn=81
for target in 23 25 27 29 31
do
    echo "AS "$asn" hijacks AS"$target

    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.0/25"
    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.128/25"

    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $seq permit ${target}.108.0.0/25"
    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $(($seq+1)) permit ${target}.108.0.128/25"
    seq=$(($seq+2))
done

seq=20
asn=82
for target in 24 26 28 30 32
do
    echo "AS "$asn" hijacks AS"$target

    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.0/25"
    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.128/25"

    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $seq permit ${target}.108.0.0/25"
    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $(($seq+1)) permit ${target}.108.0.128/25"
    seq=$(($seq+2))
done

seq=20
asn=102
for target in 64 66 68 70
do
    echo "AS "$asn" hijacks AS"$target

    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.0/25"
    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.128/25"

    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $seq permit ${target}.108.0.0/25"
    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $(($seq+1)) permit ${target}.108.0.128/25"
    seq=$(($seq+2))
done

seq=20
asn=101
for target in 63 65 67 69
do
    echo "AS "$asn" hijacks AS"$target

    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.0/25"
    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.128/25"

    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $seq permit ${target}.108.0.0/25"
    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $(($seq+1)) permit ${target}.108.0.128/25"
    seq=$(($seq+2))
done

seq=20
asn=2
for target in 44 46 48 50 52
do
    echo "AS "$asn" hijacks AS"$target

    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.0/25"
    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.128/25"

    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $seq permit ${target}.108.0.0/25"
    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $(($seq+1)) permit ${target}.108.0.128/25"
    seq=$(($seq+2))
done

seq=20
asn=1
for target in 43 45 47 49 51
do
    echo "AS "$asn" hijacks AS"$target

    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.0/25"
    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.128/25"

    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $seq permit ${target}.108.0.0/25"
    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $(($seq+1)) permit ${target}.108.0.128/25"
    seq=$(($seq+2))
done

seq=20
asn=22
for target in 84 86 88 90
do
    echo "AS "$asn" hijacks AS"$target

    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.0/25"
    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.128/25"

    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $seq permit ${target}.108.0.0/25"
    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $(($seq+1)) permit ${target}.108.0.128/25"
    seq=$(($seq+2))
done

seq=20
asn=21
for target in 83 85 87 89
do
    echo "AS "$asn" hijacks AS"$target

    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.0/25"
    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "router bgp ${asn}" -c "address-family ipv4 unicast" -c "network ${target}.108.0.128/25"

    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $seq permit ${target}.108.0.0/25"
    docker exec -it ${asn}_LONDrouter vtysh -c "conf t" -c "ip prefix-list OWN_PREFIX seq $(($seq+1)) permit ${target}.108.0.128/25"
    seq=$(($seq+2))
done
