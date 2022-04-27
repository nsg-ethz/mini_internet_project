set -o errexit
set -o pipefail
set -o nounset

. bgptest.sh

if [ "$#" -ne "2" ]; then
	err "usage: $0 id asnumber"
fi

id=$1
asnumber=$2

isnumber $id || err "id must be numeric"
isnumber $asnumber || err "AS must be numeric"

test_container="$(get_container_name $id)"

docker exec "$test_container" exabgpcli shutdown || true
docker exec -d "$test_container" exabgp -e /etc/exabgp/exabgp.env exabgp.conf

neighbors=$(echo "SELECT DISTINCT asn_b FROM ext_ifs WHERE asn_a = $asnumber" | sqlite3 -readonly bgp.db)
for neighbor in $neighbors; do
	neighbor_ips=$(echo "SELECT ip_a FROM ext_ifs WHERE asn_a = $asnumber AND asn_b = $neighbor" |
		sqlite3 -readonly bgp.db)
	for neighbor_ip in $neighbor_ips; do
		case $neighbor_ip in
			# Don't announce IXP network
			180*) continue;;
			*);;
		esac
		echo docker exec "$test_container" exabgpcli neighbor $neighbor_ip
		echo announce route $neighbor.0.0.0/8 next-hop self
		docker exec "$test_container" exabgpcli neighbor $neighbor_ip \
			announce route $neighbor.0.0.0/8 next-hop self
	done
	echo $neighbor_ips
done
