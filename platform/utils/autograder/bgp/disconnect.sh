# Disconnects all external links from an AS

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
	b=$(python3 link_bridge.py $ext_link)
	echo "Removing $ext_link from $b"
	ovs-vsctl del-port $b $ext_link
done
