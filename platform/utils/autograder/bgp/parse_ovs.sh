set -o errexit
set -o pipefail
set -o nounset

if [ "$#" != 1 ]; then
	echo "usage: $0 username" 1>&2
	exit 1
fi

if ! id "$1" > /dev/null 2>&1; then
	echo "could not find user $1"
	exit 1
fi

su "$1" -c "python3 parse_ovs.py reset"
ovs-vsctl -f csv -d string list Bridge | su "$1" -c "python3 parse_ovs.py bridge"
ovs-vsctl -f csv -d string list Port | su "$1" -c "python3 parse_ovs.py port"
ovs-vsctl -f csv -d string list Interface | su "$1" -c "python3 parse_ovs.py interface"
su "$1" -c "python3 parse_ovs.py bridge-ports"
