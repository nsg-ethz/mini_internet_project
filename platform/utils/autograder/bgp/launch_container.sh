# Launches a bgp test container together with a bridge & interfaces

set -o errexit
set -o pipefail
set -o nounset

. bgptest.sh
if [ "$#" -ne "1" ]; then
	err "usage: $0 id"
fi

id=$1

isnumber $id || err "id must be numeric"

test_container="$(get_container_name $id)"

docker run -d --name "$test_container" --net="none" --rm my_bgp
pid=$(get_container_pid $test_container)
echo $pid
ip netns attach $pid $pid
test_bridge="$(get_bridge_name $id)"
ovs-vsctl add-br "$test_bridge"

for loc in $(get_ebgp_locations); do
	host=$(get_host_interface $id $loc)
	remote=$(get_remote_interface $id $loc)
	echo "'$host' '$remote'"
	echo ip link add $host type veth peer name $remote
	ip link add $host type veth peer name $remote
	ip link set $remote netns $pid
	# TODO: necessary?
	ip link set dev $host up
	ip -n $pid link set dev $remote up
	ovs-vsctl add-port $test_bridge $host
done
