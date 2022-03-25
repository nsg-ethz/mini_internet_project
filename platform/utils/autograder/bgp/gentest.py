import sqlite3
import sys

if len(sys.argv) != 3:
    print("usage: {} id as".format(sys.argv[0]))
    sys.exit(1)

tid = int(sys.argv[1])
nr = int(sys.argv[2])

db = sqlite3.connect("file:results_{}_{}.db?rwc".format(tid, nr), uri=True)
c = db.cursor()
c.execute("PRAGMA foreign_keys = ON")
cdb = sqlite3.connect("file:config.db?ro", uri=True)
cc = cdb.cursor()
bdb = sqlite3.connect("file:bgp.db?ro", uri=True)
bc = bdb.cursor()

def iface_name(i, location):
    return "bt_r_{}_{}".format(i, location)

def get_neighbor_as(c, nr, location):
    return c.execute("""SELECT asn_b
		         FROM ifs
		          JOIN ext_ifs ON ifs.host_if = ext_ifs.host_if_a
		         WHERE c_id LIKE '%' || ? || '%'
		          AND asn = ?""", (location, nr)).fetchone()[0]

def get_external_ip(c, nr, location):
    return c.execute("""SELECT ip
		        FROM ifs
		        WHERE c_id LIKE '%' || ? || '%'
		         AND asn = ?
		         AND (bridge LIKE 'ext%' OR bridge LIKE 'ixp%')""",
                     (location, nr)).fetchone()[0]

c.execute("""CREATE TABLE info(
                key STRING NOT NULL UNIQUE,
                val STRING NOT NULL
             )""")

c.execute("""CREATE TABLE announcements(
                neighbor STRING NOT NULL,
                prefix STRING NOT NULL,
                path STRING NOT NULL
             )""")

c.execute("""CREATE TABLE hosts(
                name STRING NOT NULL UNIQUE,
                iface STRING UNIQUE,
                edge INTEGER NOT NULL,
                CHECK(edge >= 0)
             )""")

c.execute("""CREATE TABLE host_ip(
                host REFERENCES hosts(name),
                ip STRING NOT NULL
             )""")

c.execute("""CREATE TABLE test_runs(
                runid STRING NOT NULL UNIQUE,
                ts REAL NOT NULL
             )""")

c.execute("""CREATE TABLE packets(
                sr STRING NOT NULL,
                type STRING NOT NULL,
                ts_unix REAL NOT NULL,
                loc REFERENCES hosts(iface),
                runid REFERENCES test_runs(runid),
                details STRING NOT NULL,
                CHECK(sr = 'S' OR sr = 'R'),
                CHECK(type IN ('O', 'P', 'U', 'T'))
             )""")

def add_info(c, key, value):
    c.execute("""INSERT INTO info(key, val)
                 VALUES(?, ?)""", (key, value))

def add_announcement(c, neighbor, prefix, path):
    c.execute("""INSERT INTO announcements(neighbor, prefix, path)
                 VALUES(?, ?, ?)""", (neighbor, prefix, path))

def add_host_ip(c, neighbor, ip):
    c.execute("""INSERT INTO host_ip(host, ip)
                 VALUES(?, ?)""", (neighbor, ip))

add_info(c, "asnr", nr)
add_info(c, "test_container", tid)

routers = cc.execute("""SELECT nr || '_' || loc || 'router', loc
                        FROM as_config
                        JOIN router_config
                         ON as_config.router_config = router_config.name
                        WHERE nr = :nr""", {'nr': nr}).fetchall()

border_routers = list(map(lambda x: x[0], cc.execute("""SELECT DISTINCT f_loc
                               FROM all_links
                               WHERE f_loc IS NOT NULL AND f_as = :nr""", {'nr': nr}).fetchall()))

i = 1
for r, loc in routers:
    if loc in border_routers:
        neighbor_as = get_neighbor_as(bc, nr, loc)
        neighbor_ip = get_external_ip(bc, nr, loc)
        iface = iface_name(tid, loc.lower())
        ip_1 = "200.{}.0.0/16".format(10 + i)
        ip_2 = "200.{}.0.0/16".format(20 + i)
        ip_3 = "200.{}.0.0/16".format(30 + i)
        ip_4 = "200.{}.0.0/16".format(40 + i)
        ip_5 = "200.{}.0.0/16".format(50 + i)
        ip_6 = "200.{}.0.0/16".format(60 + i)
        ip_7 = "200.{}.0.0/16".format(70 + i)
        ip_8 = "200.{}.0.0/16".format(80 + i)
        ip_9 = "200.{}.0.0/16".format(90 + i)
        # Announcements with invalid paths (RPKI-wise)
        add_announcement(c, neighbor_ip, ip_1, "")
        add_announcement(c, neighbor_ip, ip_2, "{}".format(neighbor_as))
        add_announcement(c, neighbor_ip, ip_3, "500")
        # Announcements with valid paths (RPKI-wise)
        add_announcement(c, neighbor_ip, ip_4, "10000")
        add_announcement(c, neighbor_ip, ip_5, "{} 10000".format(neighbor_as))
        add_announcement(c, neighbor_ip, ip_6, "500 10000")
        # Announcements one valid path, one invalid path (RPKI-wise)
        add_announcement(c, neighbor_ip, ip_7, "")
        add_announcement(c, neighbor_ip, ip_7, "501 10000")
        add_announcement(c, neighbor_ip, ip_8, "{}".format(neighbor_as))
        add_announcement(c, neighbor_ip, ip_8, "{} 501 10000".format(neighbor_as))
        add_announcement(c, neighbor_ip, ip_9, "500")
        add_announcement(c, neighbor_ip, ip_9, "500 501 10000")

        c.execute("""INSERT INTO hosts(name, iface, edge)
                     VALUES(?, ?, ?)""", (r, iface, neighbor_as))

        add_host_ip(c, r, ip_1)
        add_host_ip(c, r, ip_2)
        add_host_ip(c, r, ip_3)

        t = cc.execute("SELECT type FROM as_config WHERE nr = ?",
                (neighbor_as,)).fetchone()[0]

        if t == 'IXP':
            # Partially from gentest.py
            rogue_as = cc.execute("""
                    WITH RECURSIVE
                        customers(x) AS
                            (SELECT ? UNION
                             SELECT DISTINCT t_as x
                             FROM customers
                             JOIN all_links
                              ON f_as = x
                             WHERE f_role = 'Provider' AND t_role = 'Customer')
                     SELECT MAX(x)
                     FROM customers
                     JOIN all_links
                      ON x = f_as
                     WHERE t_as = ?""", (nr, neighbor_as)).fetchone()[0]
            # The announcement the students need to block
            add_announcement(c, neighbor_ip, "{}.0.0.0/8".format(rogue_as), str(rogue_as))

        i += 1
    else:
        # TODO
        pass

hosts = cc.execute("""SELECT nr || '_' || loc || 'host',
                             nr || '.' || (id + 101) || '.0.1'
                      FROM as_config
                      JOIN router_config
                       ON as_config.router_config = router_config.name
                      WHERE host == 1 AND nr = :nr""", {'nr': nr}).fetchall()

for host, ip in hosts:
    c.execute("""INSERT INTO hosts(name, iface, edge)
                 VALUES(?, NULL, 0)""", (host,))
    add_host_ip(c, host, ip)

db.commit()
