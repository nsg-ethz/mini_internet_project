set -eu
if [ "$#" -ne "2" ]; then
	echo "usage: $0 id asnr" 2>&1
	exit 1
fi
sudo docker cp results_${1}_${2}.db bgptest_${1}:/results.db
sudo docker cp bgplib.py bgptest_${1}:/
sudo docker cp test_as.py bgptest_${1}:/
