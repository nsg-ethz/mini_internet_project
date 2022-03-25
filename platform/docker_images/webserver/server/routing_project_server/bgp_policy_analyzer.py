import datetime
import os
import sqlite3
import sys
from itertools import chain

from .analyzer_helpers import load_config, load_looking_glass


class ASPathError(Exception):
    pass


# Helpers to get results.
# =======================

def analyze_bgp(asn, as_data, connection_data, looking_glass_data):
    """Analyze the BGP data in the database for a given AS.

    Returns a "safe" report.
    """
    try:
        connection = sqlite3.connect(":memory:")
        load_config(connection, as_data, connection_data)
        load_looking_glass(connection, looking_glass_data)
        compute_results(connection)
        result = get_simple_as_log(connection, asn)
    finally:
        connection.close()

    last_updated = datetime.datetime.utcnow()
    return last_updated, result


def bgp_report(as_data, connection_data, looking_glass_data):
    """Return a full report of all BGP issues."""
    try:
        connection = sqlite3.connect(":memory:")
        load_config(connection, as_data, connection_data)
        load_looking_glass(connection, looking_glass_data)
        compute_results(connection)
        result = get_log(connection)
    finally:
        connection.close()

    last_updated = datetime.datetime.utcnow()
    return last_updated, result

# Helpers to split up processing.
# ===============================


def update_db(db_file, as_data, connection_data, looking_glass_data):
    """Update the database."""
    try:
        connection = sqlite3.connect(db_file)
        load_config(connection, as_data, connection_data)
        load_looking_glass(connection, looking_glass_data)
        compute_results(connection)
    finally:
        connection.close()


def load_analysis(db_file, asn):
    """Load results for a single as."""
    try:
        connection = sqlite3.connect(db_file)
        result = get_simple_as_log(connection, asn)
        # Interpret time the db file was last modified as update time.
        updated = datetime.datetime.utcfromtimestamp(os.path.getmtime(db_file))
    except sqlite3.DatabaseError:
        result = []
        updated = None
    finally:
        connection.close()

    return updated, result


def load_report(db_file):
    """Load full report."""
    try:
        connection = sqlite3.connect(db_file)
        result = get_log(connection)
        # Interpret time the db file was last modified as update time.
        updated = datetime.datetime.utcfromtimestamp(os.path.getmtime(db_file))
    except sqlite3.DatabaseError:
        result = []
        updated = None
    finally:
        connection.close()

    return updated, result


# Functions to get logs.
# ======================

def get_log(connection):
    """Get the full log.

    TODO: It would probably be nicer to have more control over the messages,
          but that would require more changes to the code.
    """
    c = connection.cursor()
    msgs = c.execute("""SELECT DISTINCT level || ': ' ||
                         CASE WHEN asnr IS NULL THEN ''
                         ELSE 'AS ' || asnr || ': ' END || message
                        FROM logs""").fetchall()
    return list(chain(*msgs))


def get_simple_as_log(connection, asn):
    """Get all 'simple' messages for an AS.

    TODO: It would probably be nicer to have more control over the messages,
          but that would require more changes to the code."""
    c = connection.cursor()
    msgs = c.execute("""SELECT DISTINCT message
                            FROM logs
                            WHERE level = 'ERROR-SIMPLE'
                             AND asnr = ?""", (asn,)).fetchall()
    return list(chain(*msgs))


# The actual work is done below.
# ==============================

def compute_results(connection):
    """The actual analysis code."""
    c = connection.cursor()

    c.execute("DROP TABLE IF EXISTS logs")
    c.execute("""CREATE TABLE logs(
                    level STRING NOT NULL,
                    asnr INTEGER,
                    message STRING NOT NULL)""")

    asnumbers = list(map(lambda x: x[0], c.execute(
        "SELECT asnumber FROM asnumbers")))

    for number in asnumbers:
        res = c.execute(
            "SELECT prefix, path FROM looking_glass WHERE asnumber = ?", (number,))
        for prefix, path in res.fetchall():
            # At the moment, ignore internal routes if the path is empty
            if str(number) == prefix.split(".")[0]:
                if path != "":
                    log(c, "ERROR", "AS {} goes to {} via AS {}".format(
                        number, prefix, path))
                continue

            # Check that the received paths are following Customer/Provider relationship
            state = "START"
            npath = str(number) + " " + str(path)
            npath = normalize_as_path(npath).split(" ")
            # The current AS and the next AS

            if len(npath) < 2:
                # Exporting the eBGP session IPs
                if prefix.split(".")[0] == "179":
                    log(c, "EBGP-IP-LEAK",
                        "eBGP IP prefix {} found at AS {}".format(prefix, number))
                elif prefix.split(".")[0] == "180":
                    log(c, "IXP-IP-LEAK",
                        "IXP IP prefix {} found at AS {}".format(prefix, number))
                else:
                    # Don't know about them
                    log(c, "ERROR", "encountered unexpected prefix {} at AS {}".format(
                        prefix, number))
                continue

            nlinks = 0
            level = "ERROR"
            from_as = npath[0]
            tested_as = npath[1]

            for f, t in zip(npath, npath[1:]):
                if f == t:
                    raise AssertionError("Invalid AS path")

                # Those errors are most likely already detected, so allow to filter them
                if nlinks == 2:
                    level = "NON-LOCAL"

                try:
                    link = get_relationship(c, f, t)
                except ASPathError:
                    log(c, "AS-PATH", "route to {} via path {}: No known link between {} and {}".format(
                        prefix, path, f, t))
                    break

                if state == "START":
                    state = link
                elif state == "Customer-Provider":
                    # Customer-Provider can go over a peer or an Provider-Customer
                    state = link
                elif state == "Peer-Peer":
                    if link != "Provider-Customer":
                        if nlinks < 2:
                            log_nr(c, level + "-SIMPLE", tested_as, "You should not export {} to AS {} "
                                   "(because it is a {} link)".format(prefix, from_as, link))
                        log(c, level, "AS {} has route to {} with path {} "
                            "contains {} link {} to {}".format(number, prefix,
                                                               path, link, f, t))
                elif state == "Provider-Customer":
                    if link != "Provider-Customer":
                        if nlinks < 2:
                            log_nr(c, level + "-SIMPLE", tested_as, "You should not export {} to AS {} "
                                   "(because it is a {} link)".format(prefix, from_as, link))
                        log(c, level, "AS {} has route to {} with path {} "
                            "contains {} link {} to {}".format(number, prefix,
                                                               path, link, f, t))

                nlinks += 1

        # Check that we receive from each customer routes to him and his customers
        for cs in customers(c, number):
            cset = set([cs])
            cset.update(recursive_customers(c, cs))

            for customer in cset:
                if not has_route_via(c, number, customer, cs):
                    log(c, "ERROR", "AS {} should have an announcement for {} from AS {}".format(
                        number, "{}.0.0.0/8".format(customer), cs))

        # Check that peers announce their customers and themself
        for pe in peers(c, number):
            pset = set([pe])
            pset.update(recursive_customers(c, pe))

            for customer in pset:
                if not has_route_via(c, number, customer, pe):
                    log(c, "ERROR", "AS {} should have an announcement for {} from AS {}".format(
                        number, "{}.0.0.0/8".format(customer), pe))

        # Check that we receive routes from all providers and their peers
        for pr in providers(c, number):
            pset = set([pr])
            pset.update(recursive_providers(c, pr))

            peerset = set()
            for provider in pset:
                peerset.update(peers(c, provider))

            pset.update(peerset)

            for provider in pset:
                if not has_route_via(c, number, provider, pr):
                    log(c, "ERROR", "AS {} should have an announcement for {} from AS {}".format(
                        number, "{}.0.0.0/8".format(provider), pr))

    # Check that the best paths are
    bestpaths = c.execute("""SELECT asnumber, prefix, CAST(path AS TEXT)
                            FROM looking_glass
                            WHERE bestpath = 1 AND path != ""
                            GROUP BY asnumber, prefix, path;""")

    for bp in bestpaths.fetchall():
        number = bp[0]
        prefix = bp[1]
        path = bp[2]
        nextas = int(path.split(" ")[0])
        destination = int(prefix.split(".")[0])

        try:
            relationship = get_relationship(c, number, nextas)
        except ASPathError:
            # This should have been discovered already by the checker above
            log(c, "AS-PATH", "Not checking bestpath from {} to {} due to bad AS path".format(
                number, prefix))
            continue

        # Sending traffic via customer is always good
        if relationship == "Provider-Customer":
            continue

        # relationship is Peer-Peer or Customer-Provider
        # so no theoretical route should exist via a customer
        for cs in customers(c, number):
            if theoretical_route_via(c, number, destination, cs):
                log(c, "EXP", "AS {} is using {} to reach prefix {} via a {} relationship "
                    "although there is a Provider-Customer route via {}".format(
                        number, nextas, prefix, relationship, cs))

        if relationship == "Peer-Peer":
            continue

        if relationship != "Customer-Provider":
            print("Expecting either Customer-Provider, Peer-Peer or Provider-Customer relationship",
                  file=sys.stderr)
            raise AssertionError("Unexpected relationship")

        for pe in peers(c, number):
            if theoretical_route_via(c, number, destination, pe):
                log(c, "EXP", "AS {} is using {} to reach prefix {} via a {} relationship "
                    "although there is a Peer-Peer route via {}".format(
                        number, nextas, prefix, relationship, pe))

        #print("from {} to {} via {}".format(number, prefix, path))

    # IXP handling:
    # No customer receives a peer route from a provider or customer
    ixp_routes = c.execute("""SELECT asnumber, location, prefix, peer, path, nexthop
                            FROM looking_glass WHERE peer LIKE '180%'""")

    for asnumber, location, prefix, peer, path, nexthop in ixp_routes.fetchall():
        nextas = str(path).split(" ")[0]

        if not nextas.isdigit():
            raise AssertionError("Expected non-empty AS path")

        if nexthop == "":
            raise AssertionError("Expected non-empty next-hop")

        # The last octet of the next-hop is the number of the AS it belongs to
        # This is to prevent trickery with the AS path
        if nexthop.split(".")[3] != nextas:
            log(c, "AS-PATH", "AS {} receives a route to {} with path {} and nexthop {} "
                "(expected the last octet of the nexthop to be idential to the first AS path entry)".format(
                    asnumber, prefix, path, nexthop))

        if int(nextas) in recursive_providers(c, asnumber):
            log_nr(c, "ERROR-SIMPLE", nextas,
                   "You advertise a route to {} via an IXP to a customer".format(prefix))
            log(c, "ERROR", "AS {} receives route to {} as a peer route from AS {} via an IXP".format(
                asnumber, prefix, nextas))

        if int(nextas) in recursive_customers(c, asnumber):
            log_nr(c, "ERROR-SIMPLE", nextas,
                   "You advertise a route to {} via an IXP to a provider".format(prefix))
            log(c, "ERROR", "AS {} receives route to {} as a peer route from AS {} via an IXP".format(
                asnumber, prefix, nextas))

    # Commit all log messages
    connection.commit()


def providers(c, nr):
    """ Returns a list of providers for AS nr """
    res = c.execute("""SELECT DISTINCT t_as FROM all_links
                       WHERE f_as = ? AND f_role = 'Customer'""",
                    (nr,))
    return map(lambda x: x[0], res.fetchall())


def peers(c, nr):
    """ Returns a list of peers for AS nr """
    res = c.execute("""SELECT DISTINCT t_as FROM all_links
                       WHERE f_as = ? AND f_role = 'Peer'
                       AND t_as IN (SELECT asnumber FROM asnumbers)""",
                    (nr,))
    return map(lambda x: x[0], res.fetchall())


def customers(c, nr):
    """ Returns a list of customers for AS nr """
    res = c.execute("""SELECT DISTINCT t_as FROM all_links
                       WHERE f_as = ? AND f_role = 'Provider'""",
                    (nr,))
    return map(lambda x: x[0], res.fetchall())


def has_path_via_ixp(c, f, t):
    r = c.execute("""SELECT *
                     FROM all_links toixp
                     JOIN all_links fromixp ON toixp.t_as = fromixp.f_as
                     WHERE toixp.t_as IN (SELECT as_number FROM as_config WHERE as_type = 'IXP')
                     AND toixp.f_as = ? AND fromixp.t_as = ?""", (f, t)).fetchone()

    return r is not None


def get_relationship(c, f, t):
    r = c.execute("""SELECT DISTINCT f_role || '-' || t_role FROM all_links
                        WHERE f_as = ? AND t_as = ?""", (f, t)).fetchall()

    # Case for routes via the IXP
    if len(r) == 0:
        if has_path_via_ixp(c, f, t):
            return "Peer-Peer"
        raise ASPathError(
            "Invalid AS path: No known connection between {} and {}".format(f, t))

    if len(r) != 1:
        print("Expected unique relationship between AS {} and {}".format(
            f, t), file=sys.stderr)
        raise AssertionError("Relationship between ASes must be unique")

    return r[0][0]


def recursive_customers(c, nr):
    """ Returns a list of all customers and customer customers and so on """
    cs = set(customers(c, nr))
    if len(cs) == 0:
        return set([])

    done = set([])
    todo = cs
    while True:
        new = set([])
        for customer in todo:
            if customer not in done:
                new.update(list(customers(c, customer)))
            done.add(customer)

        if len(new) == 0:
            break

        cs = cs.union(new)
        todo = new

    return cs


def recursive_providers(c, nr):
    """ Returns a list of all providers and provider providers and so on """
    pr = set(providers(c, nr))

    if len(pr) == 0:
        return set()

    done = set()
    todo = pr
    while True:
        new = set()

        for p in todo:
            if p not in done:
                new.update(providers(c, p))
            done.add(p)

        if len(new) == 0:
            break

        pr = pr.union(new)
        todo = new

    return pr


def has_route_via(c, number, destination, nextas):
    """ Checks if a route from AS number to AS destination exists with the next hop AS nextas """
    rc_prefix = "{:d}.0.0.0/8".format(destination)
    rc_path = "{:d} %".format(nextas)
    res = c.execute("""SELECT COUNT(*) FROM looking_glass
                       WHERE asnumber = ? AND prefix = ?
                       AND (path = ? OR path LIKE ?)""",
                    (number, rc_prefix, nextas, rc_path))
    count = res.fetchone()[0]
    return count > 0


def theoretical_route_via(c, f_as, t_as, nextas):
    """
    Checks whether there could be a route from f_as via next_as to t_as
    which follows the standard relationships.
    """

    # Find the relationship via f_as and next_as:
    r = get_relationship(c, f_as, nextas)

    if r == "Customer-Provider":
        # We assume that every AS is reachable via a provider
        return True

    cs = recursive_customers(c, nextas)
    cs.add(nextas)

    return t_as in cs


def get_tier1(c):
    res = c.execute("""SELECT asnumber FROM asnumbers
                       WHERE 'Customer'
                       NOT IN (SELECT f_role FROM all_links WHERE f_as = asnumber)""")
    return map(lambda x: x[0], res.fetchall())


def get_tier2(c):
    res = c.execute("""SELECT asnumber FROM asnumbers
                       WHERE 'Provider'
                       IN (SELECT f_role FROM all_links WHERE f_as = asnumber)
                       AND 'Customer'
                       IN (SELECT f_role FROM all_links WHERE f_as = asnumber)""")
    return map(lambda x: x[0], res.fetchall())


def get_tier3(c):
    res = c.execute("""SELECT asnumber FROM asnumbers
                       WHERE NOT EXISTS (SELECT * FROM links
                                         WHERE (f_as = asnumber AND f_role = 'Provider')
                                         OR (t_as = asnumber AND t_role = 'Provider')
                                        )""")
    return map(lambda x: x[0], res.fetchall())


def get_as_group(c, asnumber):
    """
    Retrieves all AS in the same group as asnumber.  A group is everything that
    can be reached by using Customer-Provider and Provider-Customer links
    recursivley.
    """

    new = set([asnumber])
    group = set()

    while len(new) > 0:
        nextas = new.pop()
        group.add(nextas)

        for pr in providers(c, nextas):
            if pr not in group:
                new.add(pr)

        for cs in customers(c, nextas):
            if cs not in group:
                new.add(cs)

    return group


def normalize_as_path(p):
    pe = p.split(" ")
    np = []
    prev = None

    for e in pe:
        if prev is not None and e == prev:
            continue

        if e == "":
            continue

        if not e.isdigit():
            raise ValueError("invalid element {} in AS path {}".format(e, p))

        np.append(e)
        prev = e

    return " ".join(np)


def log_nr(c, level, nr, message):
    c.execute("INSERT INTO logs VALUES (?, ?, ?)", (level, nr, message))


def log(c, level, message):
    log_nr(c, level, None, message)


def print_log(c):
    for msg in get_log(c):
        print(msg, file=sys.stderr)


def print_simple_as_html(c):
    print("<html><head><title>Looking glass checks</title></head><body>")
    print("<h2>BGP analyzer</h2>")
    print("<p>Last update: {}.</p>".format(str(datetime.datetime.now().strftime("%m/%d/%Y, %H:%M:%S"))))

    print("<ul>")
    for asnr in get_tier2(c):
        cnt = c.execute("""SELECT COUNT(*)
                           FROM (SELECT DISTINCT message
                                  FROM logs
                                  WHERE level = 'ERROR-SIMPLE'
                                   AND asnr = ?
                                )""", (asnr,)).fetchone()[0]

        if cnt != 0:
            cnt = " ({} errors detected)".format(cnt)
        else:
            cnt = ""

        print("<li><a href='#AS{}'>AS {}{}</a></li>".format(asnr, asnr, cnt))
    print("</ul>")

    for asnr in get_tier2(c):
        print("<h2 id='AS{}'>{}</h2>".format(asnr, asnr))
        msgs = c.execute("""SELECT DISTINCT message
                            FROM logs
                            WHERE level = 'ERROR-SIMPLE'
                             AND asnr = ?""", (asnr,)).fetchall()
        if len(msgs) == 0:
            continue

        for [msg] in msgs:
            print("{}<br />".format(msg))

    print("</body></html>")


# TODO(Alex): Below are the old command line options.
# We don't need them anymore, we just need the data for html.
# But maybe still useful for testing?
# html = False
# if len(sys.argv) > 1:
#     cmd = sys.argv[1]
#     if cmd == "test-has-path-via-ixp":
#         if len(sys.argv) != 4:
#             print("usage: {} {} from to".format(
#                 sys.argv[0], cmd), file=sys.stderr)
#             sys.exit(1)
#         print(has_path_via_ixp(c, int(sys.argv[2]), int(sys.argv[3])))
#         sys.exit(0)
#     elif cmd == "test-get-as-group":
#         if len(sys.argv) != 3:
#             print("usage: {} {} as".format(sys.argv[0], cmd), file=sys.stderr)
#             sys.exit(1)
#         print(get_as_group(c, int(sys.argv[2])))
#         sys.exit(0)
#     elif cmd == "test-display-tiers":
#         print("Tier 1: {}".format(", ".join(map(str, get_tier1(c)))))
#         print("Tier 2: {}".format(", ".join(map(str, get_tier2(c)))))
#         print("Tier 3: {}".format(", ".join(map(str, get_tier3(c)))))
#         sys.exit(0)
#     elif cmd == "test-normalize-as-path":
#         if len(sys.argv) != 3:
#             print(
#                 "usage: {} {} as-path".format(sys.argv[0], cmd), file=sys.stderr)
#             sys.exit(1)
#         print(normalize_as_path(sys.argv[2]))
#         sys.exit(0)
#     elif cmd == "test-display-as-info":
#         for [number] in c.execute("SELECT asnumber FROM asnumbers").fetchall():
#             print("AS {}".format(number))
#             print("    Providers: {}".format(
#                 ", ".join(map(str, providers(c, number)))))
#             print("    Peers: {}".format(", ".join(map(str, peers(c, number)))))
#             print("    Customer: {}".format(
#                 ", ".join(map(str, customers(c, number)))))
#         sys.exit(0)
#     elif cmd == "print-html":
#         html = True
#     else:
#         print("unknown command {}".format(cmd), file=sys.stderr)
#         sys.exit(1)
