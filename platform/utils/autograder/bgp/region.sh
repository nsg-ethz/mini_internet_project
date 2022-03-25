. bgptest.sh

n=${1:-1}
isnumber $n || err "number expected"
# This is more to see if it could be done in SQL
# Feel free to rewrite in Python or something
sqlite3 -readonly config.db <<-EOF
	SELECT region
	FROM (
		SELECT  row_number() OVER (ORDER BY di) region_nr,
			group_concat(asnumber, ',') region
		FROM (	SELECT asnumber, SUM(di) OVER (ORDER BY asnumber ROWS UNBOUNDED PRECEDING) di
			FROM (
				SELECT coalesce(asnumber - 1 - lag(asnumber)
					OVER (ORDER BY asnumber),1) di, asnumber
				FROM tier2
			)
		) GROUP BY di)
	WHERE region_nr = $n;
EOF
