#! /bin/bash
# Execute a command on all routers of an AS

set -eu
set -o pipefail

. bgptest.sh

containers_of_as() {
	sqlite3 -readonly config.db <<-EOF
		SELECT DISTINCT printf('%d_%srouter', nr, src)
		FROM as_config
		JOIN internal_links
		 ON as_config.internal_config = internal_links.name
                WHERE nr = '$1'
	EOF
}

if [ "$#" -ne "2" -a "$#" -ne "3" ]; then
	err "usage: $0 [-0] asnumber command"
fi

zero=false
if [ "$1" = "-0" ]; then
	zero=true
	shift
fi

as="$1"
cmd="$2"

isnumber $as || err "invalid asnumber"

[ -f config.db ] || err "config.db missing"

for c in $(containers_of_as $as); do
	if $zero; then
		echo -ne "$c\0"
	fi
	docker exec $c vtysh -c "$cmd"
	if $zero; then
		$zero && echo -ne "\0"
	fi
done
