# This is supposed to parse the output of `show ip bgp json`
# in the frr shell

import logging

logger = logging.getLogger()
logger.setLevel(logging.ERROR)
# uncomment to print all messages
# logger.setLevel(logging.INFO)


def load_config(connection, as_data, connection_data):
    """Fill database with config info."""
    c = connection.cursor()

    # Set up tables.
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

    # Load config into database.
    for asn, asdata in as_data.items():
        c.execute("""INSERT INTO as_config(as_number, as_type)
                     VALUES (?, ?)""",
                  (asn, asdata['type']))

    for _from, _to in connection_data:
        c.execute("""INSERT INTO links(f_as, f_loc, f_role, t_as, t_loc, t_role)
                     VALUES (?, ?, ?, ?, ?, ?)""",
                  (_from['asn'], _from['router'], _from['role'],
                   _to['asn'], _to['router'], _to['role']))

    connection.commit()


def load_looking_glass(connection, looking_glass_data):
    """Update database using lookingglass data."""
    c = connection.cursor()

    # Prepare table
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
    connection.commit()

    for group, groupdata in looking_glass_data.items():
        for location, looking_glass in groupdata.items():
            try:
                c = connection.cursor()
                c.execute("DELETE FROM looking_glass WHERE asnumber = ? AND "
                          "location = ?", (group, location))
                parse_lg(looking_glass, group, location, c)
                connection.commit()
            except Exception as e:
                connection.rollback()
                raise RuntimeError("Failed to parse looking glass for AS "
                                   f"{group} location {location}.") from e


def parse_lg(lg, g, l, c):
    #lg = json.load(f)

    # this happens if BGP is not configured
    if len(lg) == 1 and 'warning' in lg and lg['warning'] == "Default BGP instance not found":
        logger.warning("Group %s location %s: BGP not configured", g, l)
        return

    tv = lg['tableVersion']
    a = lg['localAS']

    if a != g:
        logger.warning(
            "Group %s has invalid as in router %s (%s instead of %s)",
            g, l, a, g
        )

    for prefix in lg['routes'].keys():
        for route in lg['routes'][prefix]:
            localpref = route.get('localpref', -1)
            path = route.get('path')
            aspath = route.get('aspath')
            if path != aspath:
                logger.info("group %s router %s prefix %s path %s aspath %s",
                            g, l, prefix, path, aspath)
            peerId = route.get('peerId')
            valid = route.get('valid', -1)
            bestpath = route.get('bestpath', False)
            if len(route.get('nexthops')) != 1:
                logger.info("nexthops for %s %s prefix %s are %s",
                            g, l, prefix, route['nexthops'])
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


# TODO(Alex): This code was never executed; is it needed?
# print(lg['vrfName'])
# print(lg['tableVersion'])
# print(lg['routerId'])
# print(lg['localAS'])
# for prefix in lg['routes'].keys():
#     print("    {}:".format(prefix))
#     for route in lg['routes'][prefix]:
#         for k in ("locPrf", "localpref", "path", "aspath", "peerId", "valid", "nexthops", "multipath"):
#             if k in route:
#                 print("        {}: {}".format(k, route[k]))
#             else:
#                 print("        {}: N/A".format(k))
