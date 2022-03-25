import sqlite3
import sys

odb = sqlite3.connect("file:ovs.db?mode=ro", uri=True)
ldb = sqlite3.connect("file:links.db?mode=ro", uri=True)
db = sqlite3.connect("bgp.db")

db.execute("""CREATE TABLE IF NOT EXISTS ifs(
                host_if STRING NOT NULL UNIQUE,
                asn INTEGER NOT NULL,
                bridge STRING NOT NULL,
                c_id STRING NOT NULL,
                c_if STRING NOT NULL,
                c_ns INTEGER NOT NULL,
                ip STRING NOT NULL)""")

db.execute("""CREATE VIEW IF NOT EXISTS ext_ifs AS
              SELECT a.host_if host_if_a, b.host_if host_if_b, a.ip ip_a, b.ip ip_b,
                     a.asn asn_a, b.asn asn_b
              FROM ifs AS a
              JOIN ifs AS b ON a.bridge = b.bridge
              WHERE (a.c_if LIKE 'ext_%' OR a.c_if LIKE 'ixp_%' OR a.c_if LIKE 'grp_%')
              AND a.host_if != b.host_if""")

query = odb.execute("""SELECT Bridge.Name, Port.Name, Interface.c_id, Interface.c_if
                       FROM Bridge
                       JOIN BridgePort on Bridge.uuid = BridgePort.b_uuid
                       JOIN Port on BridgePort.p_uuid = Port.uuid
                       JOIN Interface on Port.name = Interface.name
                       WHERE Interface.c_id != 'none'""")

ldb.execute("""CREATE TEMP TABLE pairs AS
                SELECT a.name as name_a, b.name as name_b, b.ns as ns_b, b.ip as ip_b
                FROM links AS a
                JOIN links AS b ON a.remote = b.number""")

ldb.execute("""CREATE INDEX pairs_name_a ON pairs(name_a)""")

for row in query.fetchall():
    q2 = ldb.execute("""SELECT name_a, name_b, ns_b, ip_b
                       FROM pairs
                       WHERE name_a = ?""", (row[1],)).fetchall()

    if len(q2) == 0:
        # There some interfaces for which getlinks does not find a partner
        continue

    if len(q2) != 1:
        print("Did not expect more than one entry: {}".format(q2), file=sys.stderr)
        sys.exit(1)

    q2 = q2[0]

    host_if = row[1]
    asn = row[2].split("_")[0]

    if not asn.isdigit():
        print("No as number found")
        continue

    bridge = row[0]
    c_id = row[2]
    c_if = row[3]
    c_ns = q2[2]
    ip = q2[3]

    if ip is None:
        print("No IP found")
        continue

    db.execute("""INSERT INTO ifs(host_if, asn, bridge, c_id, c_if, c_ns, ip)
                  VALUES (?, ?, ?, ?, ?, ?, ?)""",
               (host_if, asn, bridge, c_id, c_if, c_ns, ip))

db.commit()
