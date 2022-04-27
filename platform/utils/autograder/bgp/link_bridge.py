import sqlite3
import sys

if len(sys.argv) != 2:
    print("usage: {} link".format(sys.argv[0]), file=sys.stderr)
    sys.exit(1)

db = sqlite3.connect("file:ovs.db?mode=ro", uri=True)
c = db.cursor()
row = c.execute("""SELECT b.name
                   FROM Bridge AS b
                   JOIN BridgePort AS bp ON b.uuid = bp.b_uuid
                   JOIN Port AS p ON p.uuid = bp.p_uuid
                   WHERE p.name = ?""", (sys.argv[1],))
print(row.fetchone()[0])
