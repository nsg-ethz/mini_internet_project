set -eu

sqlite3 -readonly config.db <<-EOF
	SELECT group_concat(asnumber, ',')
	FROM tier2
EOF
