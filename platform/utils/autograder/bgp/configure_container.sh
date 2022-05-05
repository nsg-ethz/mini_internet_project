# Configures the test container to talk to AS nr

set -o errexit
set -o pipefail
set -o nounset
shopt -s extglob

. bgptest.sh

if [ "$#" != 2 ]; then
	err "usage: $0 id asnumber"
fi

host_if_to_lower_loc() {
	sqlite3 -readonly bgp.db <<-EOF
		SELECT lower(substr(c_id, instr(c_id, '_') + 1, 4))
		FROM ifs
		WHERE host_if = '$1'
	EOF
}

host_if_ip() {
	sqlite3 -readonly bgp.db <<-EOF
		SELECT ip
		FROM ifs
		WHERE host_if = '$1'
	EOF
}

host_if_as() {
	sqlite3 -readonly bgp.db <<-EOF
		SELECT asn
		FROM ifs
		WHERE host_if = '$1'
	EOF
}

host_if_ext_peer() {
	sqlite3 -readonly bgp.db <<-EOF
		SELECT host_if_b
		FROM ext_ifs
		WHERE host_if_a = '$1'
	EOF
}


id=$1
as=$2

isnumber $id || err "invalid id"
isnumber $as || err "invalid asnumber"

test_container=$(get_container_name $id)
test_bridge=$(get_bridge_name $id)

pid=$(get_container_pid $test_container)
ifs=$(ext_links $as)

exabgp_conf="exabgp_${id}_$as.conf"
scapy_conf="scapy_${id}_$as.conf"

> "$exabgp_conf"
> "$scapy_conf"

for i in $ifs; do
	ovs-vsctl add-port $test_bridge $i
	loc=$(host_if_to_lower_loc $i)

	if [ -z "$loc" ]; then
		err "could not find location of interface $i"
	fi

	peer_if=$(host_if_ext_peer $i)
	tc_r_if=$(get_remote_interface $id $loc)
	tc_ip=$(host_if_ip $peer_if)
	tc_as=$(host_if_as $peer_if)

	ip -n $pid link set $tc_r_if up
	ip -n $pid address flush dev $tc_r_if scope global
	ip -n $pid address add dev $tc_r_if $tc_ip/24

	local_ip=$(host_if_ip $i)
	echo "neighbor $local_ip {" >> $exabgp_conf
	echo "        description \"interface to AS $as $loc\";" >> $exabgp_conf
	echo "        router-id $tc_ip;" >> $exabgp_conf
	echo "        local-as $tc_as;" >> $exabgp_conf
	echo "        peer-as $as;" >> $exabgp_conf
	echo "        local-address $tc_ip;" >> $exabgp_conf
	echo "}" >> $exabgp_conf
	echo "" >> $exabgp_conf

	echo "conf.route.add(net=\"0.0.0.0/0\", gw=\"$local_ip\")" >> $scapy_conf
done
docker cp $exabgp_conf $test_container:/exabgp.conf
docker cp $scapy_conf $test_container:/scapy.conf
