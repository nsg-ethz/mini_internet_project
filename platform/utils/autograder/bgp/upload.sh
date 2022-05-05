set -eu

. bgptest.sh


if [ "$#" != "4" ]; then
	err "usage: $0 id use fake path"
fi

id=$1
used=$2
nr=$3
path=$4

isnumber $id || err "id must be a number"
isnumber $used || err "use must be a number"
isnumber $nr || err "fake must be a number"

ext_replacements() {
	sqlite3 -readonly bgp.db <<-EOF
		WITH
			t_ifs(c_if, c_id) AS (
				SELECT c_if, replace(c_id, '${nr}_', '${used}_')
				FROM ifs
				WHERE asn = '$nr' AND
				 (c_if LIKE 'ext%' OR c_if LIKE 'ixp%'))
			SELECT 's/' || t.c_if || '/' || n.c_if || '/'
			FROM t_ifs AS t
			JOIN ifs AS n ON t.c_id = n.c_id
			WHERE asn = '$used' AND
			 (n.c_if LIKE 'ext%' OR n.c_if LIKE 'ixp%')
	EOF
}


for i in $path/g$nr/configs/*.txt; do
	loc=${i%%.txt}
	loc=${loc##*/}
	echo $loc
	# Strip CR
	cat $i | tr -d "\r" > tmp
	sed -i "1,3d" tmp
	sed -i "1i\
		conf t\n\
		no router bgp\n\
		no router ospf\n\
		no interface *" tmp

	for er in $(ext_replacements); do
		sed -i "$er" tmp
	done

	cat tmp | sudo docker exec -i ${used}_${loc}router vtysh
done
rm tmp
