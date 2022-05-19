echo "SELECT h.name, r.name FROM links AS h JOIN links AS r ON h.remote = r.number AND r.remote = h.number WHERE h.ns=1 ORDER BY h.name;" | sqlite3 -readonly links.db
