if [ -f random-log ]; then
	echo "random-log already exists, please move it"
	exit 1
fi

if ! [ -f runner ]; then
	echo "compile the runner"
	exit 1
fi

if [ "$#" -ne 1 ]; then
	echo "usage: $0 user" 2>&1
	exit 1
fi

if ! id "$1" > /dev/null 2>&1; then
	echo "no user called $1" 2>&1
	exit 1
fi

get_random_tier2_list() {
	sqlite3 -readonly config.db <<-EOF
		SELECT group_concat(asnumber, ',')
		FROM (SELECT random() rand, asnumber
		      FROM tier2
		      ORDER BY rand
		      LIMIT 1+(abs(random())%(SELECT count(*) FROM tier2))
		     )
	EOF
}

get_tier2_count() {
	sqlite3 -readonly config.db <<-EOF
		SELECT count(*)
		FROM tier2
	EOF
}

total_tier2=$(get_tier2_count)
while true
do
	clist=$(get_random_tier2_list)
	ncontainer="$(($RANDOM % $total_tier2 + 1))"
	echo "START $(date +%s) $ncontainer $clist" | tee -a random-log
	./runner "$1" "$ncontainer" "$clist" | tee -a random-log || exit 1
	echo "END $(date +%s)" | tee -a random-log
	rm -rf results_* lg_* json_*
done
