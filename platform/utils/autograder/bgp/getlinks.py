import re
import sqlite3
import sys

def get_ip(lines):
    # Only handles one IP per interface
    for line in lines:
        match = re.match(r".*inet (\d+\.\d+\.\d+\.\d+).*", line)
        if match is not None:
            return match.group(1)
    return None

def get_veth_pair(ifname):
    match = re.match(r"(.+)@if(\d+)", ifname)
    return match.group(1), match.group(2)

def add_link(c, lines):
    line = lines[0]
    match = re.match(r"(\d+): (.+): <", line)

    if match is None:
        print("Could not match line '{}'".format(line), file=sys.stderr)
        sys.exit(1)

    ns = sys.argv[1]
    number = match.group(1)
    name = match.group(2)
    if name != "IXP":
        name, remote = get_veth_pair(name)
    else:
        remote = None

    ip = get_ip(lines[1:])

    # This expects IXP interfaces being added at the end
    if name == "IXP":
        c.execute("UPDATE links SET ip = ? WHERE ns = ?", (ip, ns))

    c.execute("""INSERT INTO links (ns, number, name, remote, ip)
                 VALUES (?, ?, ?, ?, ?)""", (ns, number, name, remote, ip))

db = sqlite3.connect("links.db")
c = db.cursor();
c.execute("""
    CREATE TABLE IF NOT EXISTS links (
            ns INTEGER NOT NULL,
            number INTEGER NOT NULL,
            name STRING NOT NULL,
            remote INTEGER,
            ip STRING
    );
""")

if len(sys.argv) != 2:
    print("usage: {} ns".format(sys.argv[0]), file=sys.stderr)
    sys.exit(1)

if sys.argv[1] == "reset":
    c.execute("DELETE FROM links")
    db.commit()
    sys.exit(0)

lines = []
while True:
    try:
        line = input("")
    except EOFError:
        break

    if len(lines) == 0 or not line[0].isdigit():
        lines.append(line)
        continue

    add_link(c, lines)
    lines = [line]

if len(lines) > 0:
    add_link(c, lines)

db.commit()
