import sqlite3
import os.path
import sys

if len(sys.argv) != 2:
    print("usage: {} config_directory".format(sys.argv[0]), file=sys.stderr)
    sys.exit(1)

db = sqlite3.connect("as.db")
c = db.cursor()

c.execute("DROP TABLE IF EXISTS as_config")
c.execute("""CREATE TABLE as_config (
        as_number INTEGER PRIMARY KEY,
        as_type STRING NOT NULL,
        CHECK(as_type = 'AS' OR as_type = 'IXP'))""")

c.execute("DROP VIEW IF EXISTS asnumbers")
c.execute("""CREATE VIEW asnumbers AS
                SELECT as_number asnumber
                FROM as_config
                WHERE as_type = 'AS'""")

c.execute("DROP TABLE IF EXISTS links")
c.execute("""CREATE TABLE links (
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

c.execute("DROP VIEW IF EXISTS all_links")
c.execute("""CREATE VIEW all_links AS
             SELECT f_as, f_loc, f_role, t_as, t_loc, t_role FROM links UNION
             SELECT t_as, t_loc, t_role, f_as, f_loc, f_role FROM links""")

c.execute("PRAGMA foreign_keys = ON")

with open(os.path.join(sys.argv[1], "AS_config.txt")) as f:
    for line in f:
        fields = line.split("\t")

        c.execute("""INSERT INTO as_config(as_number, as_type)
                     VALUES (?, ?)""",
                  (fields[0], fields[1]))

with open(os.path.join(sys.argv[1], "external_links_config.txt")) as f:
    for line in f:
        fields = line.split("\t")

        if fields[1] == 'N/A':
            fields[1] = None

        if fields[4] == 'N/A':
            fields[4] = None

        c.execute("""INSERT INTO links(f_as, f_loc, f_role, t_as, t_loc, t_role)
                     VALUES (?, ?, ?, ?, ?, ?)""",
                  (fields[0], fields[1], fields[2], fields[3], fields[4], fields[5]))

db.commit()
