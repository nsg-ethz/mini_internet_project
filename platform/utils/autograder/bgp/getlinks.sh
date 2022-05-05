# Collect veth pairs between the host ns and the docker ns

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

# So we find the host ns as well
if ! ip netns | grep "^1$" > /dev/null 2>&1; then
	ip netns attach 1 1
fi

su "$1" -c "python3 getlinks.py reset"

for ns in $(ip netns | cut -f1 -d" " | sort -n); do
	echo "NS $ns"
	if ! ip -n $ns a > /dev/null 2>&1; then
		echo "Skipping $ns"
		continue
	fi
	ip -n $ns address show type veth | su "$1" -c "python3 getlinks.py $ns"
done

ixpns=$(su "$1" -c "echo \"SELECT DISTINCT ns FROM links WHERE name LIKE 'grp%'\" | sqlite3 -readonly links.db")
for ixp in $ixpns; do
	ip -n $ixp address show dev IXP | su "$1" -c "python3 getlinks.py $ixp"
done
