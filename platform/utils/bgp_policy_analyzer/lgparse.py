# This is supposed to parse the output of `show ip bgp json`
# in the frr shell

import json
import os
import sys
import sqlite3

LOCATIONS = ["BROO", "NEWY", "CHAR", "PITT", "DETR", "CHIC", "STLO", "NASH"]
GROUPS = [3, 4, 5, 6]

def parse_lg(f, g, l, c):
    lg = json.load(f)
    tv = lg['tableVersion']
    #print(lg['routerId'])
    a = lg['localAS']

    if a != g:
        print("Group {} has invalid as in router {} ({} instead of {})".format(g, l, a, g),
                file=sys.stderr)

    for prefix in lg['routes'].keys():
        #print("    {}:".format(prefix))
        for route in lg['routes'][prefix]:
            localpref = route.get('localpref', -1)
            path = route.get('path')
            aspath = route.get('aspath')
            if path != aspath:
                print("group {} router {} prefix {} path {} aspath {}".format(g, l, prefix,
                    path, aspath), file=sys.stderr)
            peerId = route.get('peerId')
            valid = route.get('valid')
            bestpath = route.get('bestpath', False)
            if len(route.get('nexthops')) != 1:
                print("nexthops for {} {} prefix {} are {}".format(g, l, prefix,
                    route['nexthops']))
            multipath = route.get('multipath', 0)
            med = route.get('med', -1)
            metric = route.get('metric', -1)
            weight = route.get('weight')
            c.execute("""INSERT INTO looking_glass (
                tableVersion, asnumber, location, prefix, valid, bestpath,
                multipath, med, metric, localpref, weight, peer, path, nexthop)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (tv, g, l, prefix, valid, bestpath, multipath, med, metric, localpref, weight,
                    peerId, path, route['nexthops'][0]['ip']))

if len(sys.argv) != 2:
    print("usage: {} dir".format(sys.argv[0]), file=sys.stderr)
    sys.exit(1)

db = sqlite3.connect("as.db")
c = db.cursor()

c.execute("""CREATE TABLE IF NOT EXISTS looking_glass (
        id INTEGER PRIMARY KEY,
        tableVersion INTEGER NOT NULL,
        asnumber INTEGER NOT NULL,
        location STRING NOT NULL,
        prefix STRING NOT NULL,
        valid INTEGER NOT NULL,
        bestpath INTEGER NOT NULL,
        multipath INTEGER NOT NULL,
        med INTEGER NOT NULL,
        metric INTEGER NOT NULL,
        localpref INTEGER NOT NULL,
        weight INTEGER NOT NULL,
        peer STRING NOT NULL,
        path STRING NOT NULL,
        nexthop STRING NOT NULL
        )""")
c.execute("DELETE FROM looking_glass")
db.commit()

for g in GROUPS:
    for l in LOCATIONS:
        p = os.path.join(sys.argv[1], "g{:d}".format(g), l, "looking_glass_json.txt")
        if os.path.isfile(p):
            c = db.cursor()
            print (p)
            with open(p) as f:
                parse_lg(f, g, l, c)
            db.commit()

sys.exit(0)
print(lg['vrfName'])
print(lg['tableVersion'])
print(lg['routerId'])
print(lg['localAS'])
for prefix in lg['routes'].keys():
    print("    {}:".format(prefix))
    for route in lg['routes'][prefix]:
        for k in ("locPrf", "localpref", "path", "aspath", "peerId", "valid", "nexthops", "multipath"):
            if k in route:
                print("        {}: {}".format(k, route[k]))
            else:
                print("        {}: N/A".format(k))

