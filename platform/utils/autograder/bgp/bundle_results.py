import sqlite3
import sys

if len(sys.argv) != 3:
    print("usage: {} id as".format(sys.argv[0]), file=sys.stderr)
    sys.exit(1)

tid = int(sys.argv[1])
asnr = int(sys.argv[2])

db = sqlite3.connect("file:results_{}_{}.db?mode=rw".format(tid, asnr), uri=True)
c = db.cursor()

c.execute("""CREATE TABLE files(
                container STRING NOT NULL,
                cmd STRING NOT NULL,
                result STRING NOT NULL,
                CHECK(cmd = 'JSON' OR cmd = 'LG')
             )""")


for cmd in ('lg', 'json'):
    with open("{}_{}_{}".format(cmd, tid, asnr)) as f:
        fields = f.read().split("\0")
        for container, result in zip(fields[0::2], fields[1::2]):
            c.execute("""INSERT INTO files(container, cmd, result)
                         VALUES(?, upper(?), ?)""", (container, cmd, result))

    db.commit()
