# Cleans the bgp test container together with bridge & interfaces

set -o errexit
set -o pipefail
set -o nounset

. bgptest.sh

if [ "$#" -ne 1 ]; then
	err "usage: $0 id"
fi

id=$1

isnumber $id || err "id must be numeric"

test_container="$(get_container_name $id)"
test_bridge="$(get_bridge_name $id)"

docker kill $test_container || true
ovs-vsctl del-br $test_bridge || true

for loc in $(get_ebgp_locations); do
	host="$(get_host_interface $id $loc)"
	remote="$(get_remote_interface $id $loc)"
	echo ip link del $host
	ip link del $host
done
