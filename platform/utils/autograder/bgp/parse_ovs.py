import csv
import re
import sqlite3
import subprocess
import sys

db = sqlite3.connect("ovs.db")
c = db.cursor();
c.execute("""
    CREATE TABLE IF NOT EXISTS Bridge (
            uuid STRING NOT NULL UNIQUE,
            name STRING NOT NULL,
            ports STRING NOT NULL
    );
""")
c.execute("""
    CREATE TABLE IF NOT EXISTS Port (
            uuid STRING NOT NULL UNIQUE,
            name STRING NOT NULL,
            interfaces STRING NOT NULL
    );
""")
c.execute("""
    CREATE TABLE IF NOT EXISTS Interface (
            uuid STRING NOT NULL UNIQUE,
            name STRING NOT NULL,
            c_id STRING NOT NULL,
            c_if STRING NOT NULL
    );
""")
c.execute("""
    CREATE TABLE IF NOT EXISTS BridgePort (
            b_uuid STRING NOT NULL REFERENCES Bridge(uuid),
            p_uuid STRING NOT NULL REFERENCES Port(uuid)
    );
""")

def loadbridges(c):
    d = csv.DictReader(sys.stdin)

    for row in d:
        uuid = row['_uuid']
        name = row['name']
        ports = row['ports']

        # For some reason ovs-vsctl adds quotes around some names
        if name[0] == '"' and name[-1] == '"':
            name = name[1:-1]

        c.execute("""INSERT INTO Bridge (uuid, name, ports)
                     VALUES (?, ?, ?)""",
                  (uuid, name, ports))

def loadports(c):
    d = csv.DictReader(sys.stdin)

    for row in d:
        uuid = row['_uuid']
        name = row['name']
        interfaces = row['interfaces']

        # For some reason ovs-vsctl adds quotes around some names
        if name[0] == '"' and name[-1] == '"':
            name = name[1:-1]

        c.execute("""INSERT INTO Port (uuid, name, interfaces)
                     VALUES (?, ?, ?)""",
                  (uuid, name, interfaces))

def loadinterfaces(c):
    d = csv.DictReader(sys.stdin)

    for row in d:
        uuid = row['_uuid']
        name = row['name']
        external_ids = row['external_ids']

        # For some reason ovs-vsctl adds quotes around some names
        if name[0] == '"' and name[-1] == '"':
            name = name[1:-1]

        if external_ids != "{}":
            #{container_id="3_LONDrouter", container_iface=ext_1_ZURI}
            match = re.match(r'{container_id=(.*), container_iface=(.*)}', external_ids)

            if match is None:
                print("Could not match external_ids '{}'".format(external_ids), file=sys.stderr)
                sys.exit(1)

            c_id = match.group(1)
            c_if = match.group(2)

            # For some reason ovs-vsctl adds quotes around some names
            if c_id[0] == '"' and c_id[-1] == '"':
                c_id = c_id[1:-1]

            # For some reason ovs-vsctl adds quotes around some names
            if c_if[0] == '"' and c_if[-1] == '"':
                c_if = c_if[1:-1]

        else:
            c_id = "none"
            c_if = "none"

        c.execute("""INSERT INTO Interface (uuid, name, c_id, c_if)
                     VALUES (?, ?, ?, ?)""",
                  (uuid, name, c_id, c_if))

def add_bridge_ports(c):
    for row in c.execute("SELECT uuid, ports FROM Bridge").fetchall():
        b_uuid = row[0]
        ports = row[1]

        if ports[0] == "[" and ports[-1] == "]":
            ports = ports[1:-1]
        else:
            print("Could not parse ports list '{}'".format(ports), file=sys.stderr)
            sys.exit(1)

        for p_uuid in map(lambda x: x.strip(), ports.split(",")):
            c.execute("""INSERT INTO BridgePort (b_uuid, p_uuid)
                         VALUES (?, ?)""", (b_uuid, p_uuid))

if len(sys.argv) != 2:
    print("usage: {} table".format(sys.argv[0]), file=sys.stderr)
    sys.exit(1)

c.execute("PRAGMA foreign_keys=1")
if sys.argv[1] == "reset":
    c.execute("DELETE FROM BridgePort")
    c.execute("DELETE FROM Bridge")
    c.execute("DELETE FROM Port")
    c.execute("DELETE FROM Interface")
    db.commit()
elif sys.argv[1] == "bridge":
    loadbridges(c)
    db.commit()
elif sys.argv[1] == "port":
    loadports(c)
    db.commit()
elif sys.argv[1] == "interface":
    loadinterfaces(c)
    db.commit()
elif sys.argv[1] == "bridge-ports":
    add_bridge_ports(c)
    db.commit()
else:
    print("Unknown command {}".format(sys.argv[1]), file=sys.stderr)
    sys.exit(1)
