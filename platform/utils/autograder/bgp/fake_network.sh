# Connect an AS pretending it is another AS

set -o errexit
set -o pipefail
set -o nounset
shopt -s extglob

. bgptest.sh

if [ "$#" != 3 ]; then
	err "usage: $0 id as-to-use as-to-fake"
fi

host_if_to_lower_loc() {
	sqlite3 -readonly bgp.db <<-EOF
		SELECT lower(substr(c_id, instr(c_id, '_') + 1, 4))
		FROM ifs
		WHERE host_if = '$1'
	EOF
}

host_if_to_loc() {
	sqlite3 -readonly bgp.db <<-EOF
		SELECT substr(c_id, instr(c_id, '_') + 1, 4)
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

host_if_ext_from_c_id() {
	sqlite3 -readonly bgp.db <<-EOF
		SELECT host_if
		FROM ifs
		WHERE c_id = '$1'
		 AND (c_if LIKE 'ixp%' OR c_if LIKE 'ext%')
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
as_use=$2
as_fake=$3

isnumber $id || err "invalid id"
isnumber $as_use || err "invalid as-to-use"
isnumber $as_fake || err "invalid as-to-fake"

test_container=$(get_container_name $id)
test_bridge=$(get_bridge_name $id)

pid=$(get_container_pid $test_container)
ifs=$(ext_links $as_use)

exabgp_conf="exabgp_${id}_${as_use}.conf"
scapy_conf="scapy_${id}_${as_use}.conf"

> "$exabgp_conf"
> "$scapy_conf"

chown martin:martin "$exabgp_conf" "$scapy_conf"

for i in $ifs; do
	ovs-vsctl add-port $test_bridge $i
	loc=$(host_if_to_lower_loc $i)
	LOC=$(host_if_to_loc $i)

	# The interface in the network to fake
	echo "${as_fake}_${LOC}router"
	fake_if=$(host_if_ext_from_c_id "${as_fake}_${LOC}router")
	echo $fake_if

	peer_if=$(host_if_ext_peer $fake_if)
	tc_r_if=$(get_remote_interface $id $loc)
	tc_ip=$(host_if_ip $peer_if)
	tc_as=$(host_if_as $peer_if)

	ip -n $pid link set $tc_r_if up
	ip -n $pid address flush dev $tc_r_if scope global
	ip -n $pid address add dev $tc_r_if $tc_ip/24

	local_ip=$(host_if_ip $fake_if)
	echo "neighbor $local_ip {" >> $exabgp_conf
	echo "        description \"interface to AS $as_use posing as $as_fake $loc\";" >> $exabgp_conf
	echo "        router-id $tc_ip;" >> $exabgp_conf
	echo "        local-as $tc_as;" >> $exabgp_conf
	echo "        peer-as $as_fake;" >> $exabgp_conf
	echo "        local-address $tc_ip;" >> $exabgp_conf
	echo "}" >> $exabgp_conf
	echo "" >> $exabgp_conf

	echo "conf.route.add(net=\"0.0.0.0/0\", gw=\"$local_ip\")" >> $scapy_conf
done
docker cp $exabgp_conf $test_container:/exabgp.conf
docker cp $scapy_conf $test_container:/scapy.conf
