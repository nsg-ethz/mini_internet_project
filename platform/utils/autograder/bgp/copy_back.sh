set -eu
if [ "$#" -ne "3" ]; then
	echo "usage: $0 id asnr user" 2>&1
	exit 1
fi
if ! id "$3" > /dev/null 2>&1; then
	echo "invalid user $3"
	exit 1
fi
sudo docker cp bgptest_${1}:/results.db results_${1}_${2}.db
sudo docker exec bgptest_${1} rm results.db
chown ${3} results_${1}_${2}.db
