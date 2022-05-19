# Library for commonly used functions/variables

err() {
	echo "$@" 1>&2
	exit 1
}

isnumber() {
	local nr=$1
	if [ -n "$(echo "$nr" | tr -d "[[:digit:]]")" ]; then
		return 1
	fi
	return 0
}

get_container_name() {
	local id=$1

	isnumber $id || err "id is not a number"

	echo "bgptest_$id"
}

get_host_interface() {
	local id=$1 loc=$2

	isnumber $id || err "id is not a number"

	echo "bt_h_${id}_$loc"
}

get_remote_interface() {
	local id=$1 loc=$2

	isnumber $id || err "id is not a number"

	echo "bt_r_${id}_$loc"
}

get_bridge_name() {
	local id=$1

	isnumber $1 || err "id is not a number"

	echo "bgptest-br-$id"
}

get_container_pid() {
	local container=$1

	docker inspect -f '{{.State.Pid}}' "$container"
}

get_ebgp_locations() {
	sqlite3 -readonly config.db <<-EOF
		SELECT DISTINCT lower(f_loc)
		FROM all_links
		WHERE f_loc IS NOT NULL
		ORDER BY f_loc
	EOF
}

ext_links() {
	local as=$1

	isnumber $as || err "as is not a number"

	sqlite3 -readonly bgp.db <<-EOF
		SELECT host_if
		FROM ifs
		WHERE (c_if LIKE 'ext%' OR c_if LIKE 'ixp%') AND asn = '${as}'
	EOF
}
