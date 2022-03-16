#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

for py in cfparse.py lgparse.py lganalyze.py
do
	if ! [ -f "$py" ]
	then
		echo "$0: expected script called $py"
		exit 1
	fi
done

cfparse=$(realpath cfparse.py)
lgparse=$(realpath lgparse.py)
lganalyze=$(realpath lganalyze.py)

cd "${0%/*}"

testcase () {
	local test_dir=$1

	for dir in conf lg_bad lg_good
	do
		if ! [ -d "$test_dir/$dir" ]
		then
			echo "$0: $test_dir: expected directory $test_dir/$dir"
			return 1
		fi
	done

	python3 "$cfparse" $test_dir/conf
	python3 "$lgparse" $test_dir/lg_good
	python3 "$lganalyze" > lg_stdout  2> lg_stderr

	if [ -n "$(cat lg_stderr)" ]
	then
		echo "$0: $test_dir: did not expected errors in lg_good"
		echo "$0: $test_dir: check lg_stdout and lg_stderr"
		return 1
	fi

	python3 "$lgparse" $test_dir/lg_bad
	python3 "$lganalyze" > lg_stdout  2> lg_stderr

	if ! cmp <(sort lg_stderr) <(sort $test_dir/lg_expected)
	then
		echo "$0: $test_dir: errors do not match expected errors"
		echo "$0: $test_dir: check lg_stderr and lg_expected"
		return 1
	fi

	rm lg_stdout lg_stderr as.db
}

TEST_CASES="test01 test02 test03 test04 test05 test06 test07 test08"

rm -f lg_stdout lg_stderr as.db

for t in $TEST_CASES
do
	if ! testcase $t
	then
		echo "$0: $t: failed"
		# Exit early so that the output files can be inspected
		exit 1
	fi
done
echo OK
