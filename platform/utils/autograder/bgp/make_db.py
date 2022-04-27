import os
import sqlite3
import sys

def split_at_ws(line):
    n = ""
    ws = False
    for ch in line:
        if ch.isspace():
            if ws:
                continue
            else:
                ws = True
                ch = " "
        else:
            ws = False
        n += ch
    return n.split(" ")

if len(sys.argv) != 2:
    print("usage: {} config-dir".format(sys.argv[0]), file=sys.stderr)
    sys.exit(1)

db = sqlite3.connect("config.db")
c = db.cursor()
c.execute("PRAGMA foreign_keys = ON")

c.execute("""CREATE TABLE as_config(
                nr INTEGER PRIMARY KEY,
                type STRING NOT NULL,
                router_config STRING,
                internal_config STRING,
                layer2_switches STRING,
                layer2_hosts STRING,
                layer2_links STRING,
                CHECK(type = 'AS' OR type = 'IXP')
             )""")
c.execute("""CREATE VIEW asnumbers AS
                SELECT nr asnumber
                FROM as_config
                WHERE type = 'AS'""")

with open(os.path.join(sys.argv[1], "AS_config.txt")) as f:
    for line in f:
        fields = split_at_ws(line)

        for i in range(len(fields)):
            if fields[i] == "N/A":
                fields[i] = None

        c.execute("""INSERT INTO as_config(nr, type, router_config, internal_config,
                                           layer2_switches, layer2_hosts,
                                           layer2_links)
                     VALUES (?, ?, ?, ?, ?, ?, ?)""",
                  (fields[0], fields[1], fields[3], fields[4], fields[5], fields[6],
                      fields[7]))

db.commit()

c.execute("""CREATE TABLE router_config(
                name STRING NOT NULL,
                id INTEGER NOT NULL,
                loc STRING NOT NULL,
                ext STRING,
                l2_loc STRING,
                host INTEGER NOT NULL,
                CHECK(host = 1 OR host = 0)
                UNIQUE(name, id),
                UNIQUE(name, loc)
             )""")

for [rc] in c.execute("SELECT DISTINCT router_config FROM as_config WHERE router_config IS NOT NULL").fetchall():
    with open(os.path.join(sys.argv[1], rc)) as f:
        j = 1
        for line in f:
            fields = split_at_ws(line)

            for i in range(len(fields)):
                if fields[i] == "N/A":
                    fields[i] = None

            l2_loc = None
            if len(fields[2]) > 3 and fields[2][:3] == "L2-":
                l2_loc = fields[2][3:]

            host = False
            if len(fields[2]) > 5 and fields[2][:5] == "host:":
                host = True

            c.execute("""INSERT INTO router_config(name, id, loc, ext, l2_loc, host)
                         VALUES(?, ?, ?, ?, ?, ?)""", (rc, j, fields[0], fields[1], l2_loc, host))
            j += 1

db.commit()

c.execute("""CREATE TABLE internal_links(
                name STRING NOT NULL,
                src STRING NOT NULL,
                dst STRING NOT NULL,
                UNIQUE(name, src, dst)
            )""")


for [ic] in c.execute("SELECT DISTINCT internal_config FROM as_config WHERE internal_config IS NOT NULL").fetchall():
    with open(os.path.join(sys.argv[1], ic)) as f:
        for line in f:
            fields = split_at_ws(line)
            c.execute("""INSERT INTO internal_links(name, src, dst)
                         VALUES (?, ?, ?)""", (ic, fields[0], fields[1]))
            c.execute("""INSERT INTO internal_links(name, src, dst)
                         VALUES (?, ?, ?)""", (ic, fields[1], fields[0]))

db.commit()

c.execute("""CREATE TABLE layer2_switches(
                name STRING NOT NULL,
                network STRING NOT NULL,
                l2_loc STRING NOT NULL,
                l3_loc STRING,
                mac STRING NOT NULL UNIQUE,
                CHECK(LENGTH(mac) == 17))""")

for [l2s] in c.execute("SELECT DISTINCT layer2_switches FROM as_config WHERE layer2_switches IS NOT NULL"):
    with open(os.path.join(sys.argv[1], l2s)) as f:
        for line in f:
            fields = split_at_ws(line)
            for i in range(len(fields)):
                if fields[i] == "N/A":
                    fields[i] = None
            c.execute("""INSERT INTO layer2_switches(name, network, l2_loc, l3_loc, mac)
                         VALUES(?, ?, ?, ?, ?)""",
                      (l2s, fields[0], fields[1], fields[2], fields[3]))

db.commit()

c.execute("""CREATE TABLE layer2_hosts(
                name STRING NOT NULL,
                hostname STRING NOT NULL,
                network STRING NOT NULL,
                l2_loc STRING NOT NULL,
                vlan INTEGER NOT NULL)""")

for [l2h] in c.execute("SELECT DISTINCT layer2_hosts FROM as_config WHERE layer2_hosts IS NOT NULL").fetchall():
    with open(os.path.join(sys.argv[1], l2h)) as f:
        for line in f:
            fields = split_at_ws(line)
            c.execute("""INSERT INTO layer2_hosts(name, hostname, network, l2_loc, vlan)
                         VALUES(?, ?, ?, ?, ?)""",
                      (l2h, fields[0], fields[2], fields[3], fields[6]))

db.commit()

c.execute("""CREATE TABLE layer2_links(
                name STRING NOT NULL,
                f_network STRING NOT NULL,
                f_l2_loc STRING NOT NULL,
                t_network STRING NOT NULL,
                t_l2_loc STRING NOT NULL)""")

c.execute("""CREATE VIEW all_l2_links AS
                SELECT name, f_network, f_l2_loc, t_network, t_l2_loc
                FROM layer2_links
                UNION
                SELECT name, t_network, t_l2_loc, f_network, f_l2_loc
                FROM layer2_links""")

for [l2l] in c.execute("SELECT DISTINCT layer2_links FROM as_config WHERE layer2_links IS NOT NULL").fetchall():
    with open(os.path.join(sys.argv[1], l2l)) as f:
        for line in f:
            fields = split_at_ws(line)
            c.execute("""INSERT INTO layer2_links(name, f_network, f_l2_loc, t_network, t_l2_loc)
                         VALUES(?, ?, ?, ?, ?)""",
                      (l2l, fields[0], fields[1], fields[2], fields[3]))

db.commit()

# Copied from cfparse.py
c.execute("""CREATE TABLE links(
        id INTEGER PRIMARY KEY,
        f_as INTEGR REFERENCES as_config,
        f_loc STRING,
        f_role STRING NOT NULL,
        t_as INTEGER REFERENCES as_config,
        t_loc STRING,
        t_role STRING NOT NULL,
        CHECK((f_role = 'Customer' AND t_role = 'Provider')
              OR (f_role = 'Provider' AND t_role = 'Customer')
              OR (f_role = 'Peer' AND t_role = 'Peer')))""")

c.execute("""CREATE VIEW all_links AS
             SELECT f_as, f_loc, f_role, t_as, t_loc, t_role FROM links UNION
             SELECT t_as, t_loc, t_role, f_as, f_loc, f_role FROM links""")

c.execute("""CREATE VIEW tier2 AS
                SELECT asnumber
                FROM asnumbers
                WHERE 'Customer' IN (SELECT f_role FROM all_links WHERE f_as = asnumber)
                  AND 'Provider' IN (SELECT f_role FROM all_links WHERE f_as = asnumber)""")

with open(os.path.join(sys.argv[1], "external_links_config.txt")) as f:
    for line in f:
        fields = split_at_ws(line)

        if fields[1] == 'N/A':
            fields[1] = None

        if fields[4] == 'N/A':
            fields[4] = None

        c.execute("""INSERT INTO links(f_as, f_loc, f_role, t_as, t_loc, t_role)
                     VALUES (?, ?, ?, ?, ?, ?)""",
                  (fields[0], fields[1], fields[2], fields[3], fields[4], fields[5]))

db.commit()
