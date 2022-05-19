import sqlite3
import subprocess
import time

from scapy.all import *

from bgplib import *

db = sqlite3.connect("results.db")
c = db.cursor()
c.execute("PRAGMA foreign_keys = ON")
c.execute("INSERT INTO info(key, val) VALUES('start', julianday())")

nr = c.execute("SELECT val FROM info WHERE key = 'asnr'").fetchone()[0]

for nip, prefix, path in c.execute("SELECT neighbor, prefix, path FROM announcements").fetchall():
    print("Announcing {} to {} with path {}".format(prefix, nip, path))
    subprocess.run(['exabgpcli', 'neighbor', nip, 'announce', 'route', prefix, 'next-hop', 'self', "as-path", "[{}]".format(path)])
    # runs too often
    conf.route.add(net="0.0.0.0/0", gw=nip)

# Leave time for BGP to converge
time.sleep(5)

print("Saving exabgp looking glasses")
r = subprocess.run(["exabgpcli", "show", "adj-rib", "in", "extensive"], capture_output=True)
c.execute("CREATE TABLE lg(lg STRING NOT NULL)")
c.execute("INSERT INTO lg(lg) VALUES(?)", (r.stdout,))
db.commit()

test = ASTest(db.cursor(), nr, "connectivity")

ifaces = list(map(lambda x: x[0], c.execute("""SELECT DISTINCT iface
                                               FROM hosts
                                               WHERE iface IS NOT NULL"""
                                           ).fetchall()))

a = AsyncSniffer(iface=ifaces, filter="udp or icmp")
a.start()

routers = c.execute("""SELECT name, ip, iface, edge
                       FROM hosts
                       JOIN host_ip
                        ON hosts.name = host_ip.host
                       WHERE edge > 0
                       GROUP BY name""").fetchall()

for f, f_ip, iface, edge in routers:
    for t, t_ip, t_iface, t_edge in routers:
        if f == t:
            continue

        print("udp {} {} {} {} {}".format(iface, f, f_ip, t, t_ip))
        test.test_send_udp(iface, f, f_ip, t, t_ip)
        test.test_send_udp(iface, f, f_ip, t, "{}.0.0.0/8".format(edge))

db.commit()
test.reset("ping")

hosts = c.execute("""SELECT name, ip
                     FROM hosts
                     JOIN host_ip
                      ON hosts.name = host_ip.host
                     WHERE edge = 0""").fetchall()

for f, f_ip, iface, edge in routers:
    for t, t_ip in hosts:
        print("ping {} {} {} {} {}".format(iface, f, f_ip, t, t_ip))
        test.test_ping_host(iface, f, f_ip, t, t_ip)

db.commit()
test.reset("traceroute")

for f, f_ip, iface, edge in routers:
    for t, t_ip, t_iface, t_edge in routers:
        if f == t:
            continue
        print("traceroute {} {} {} {} {}".format(iface, f, f_ip, t, t_ip))
        test.test_do_traceroute(iface, f, f_ip, t, t_ip)
        test.test_do_traceroute(iface, f, f_ip, t, "{}.0.0.0/8".format(edge))

    for t, t_ip in hosts:
        print("traceroute {} {} {} {} {}".format(iface, f, f_ip, t, t_ip))
        test.test_do_traceroute(iface, f, f_ip, t, t_ip)

time.sleep(5)

a.stop()
test.log_received(a.results)
c.execute("INSERT INTO info(key, val) VALUES('end', julianday())")
db.commit()
