# Connects an AS back

set -o errexit
set -o pipefail
set -o nounset

. bgptest.sh

if [ "$#" != 1 ]; then
	err "usage: $0 asnumber"
fi

as=$1

isnumber $as || err "as must be a number"

ext_links=$(ext_links $as)

for ext_link in $ext_links; do
	echo "Bridge is" $(python3 link_bridge.py $ext_link)
	b=$(python3 link_bridge.py $ext_link)
	c_id=$(echo "SELECT c_id FROM Interface WHERE name = '$ext_link'" | sqlite3 -readonly ovs.db)
	c_if=$(echo "SELECT c_if FROM Interface WHERE name = '$ext_link'" | sqlite3 -readonly ovs.db)
	current_bridge=$(ovs-vsctl port-to-br $ext_link || echo "")
	if [ "$current_bridge" != "$b" ]; then
		[ -n "$current_bridge" ] && ovs-vsctl del-port $current_bridge $ext_link
		echo "Adding $ext_link to $b with id $c_id and iface $c_if"
		ovs-vsctl add-port $b $ext_link
		ovs-vsctl set interface $ext_link external_ids:container_id=$c_id external_ids:container_iface=$c_if
	fi
done
