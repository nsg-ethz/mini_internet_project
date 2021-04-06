import sqlite3
import sys

db = sqlite3.connect("file:as.db?mode=ro", uri=True)

def providers(c, nr):
    """ Returns a list of providers for AS nr """
    res = c.execute("""SELECT DISTINCT t_as FROM all_links
                       WHERE f_as = ? AND f_role = 'Customer'""",
                    (nr,))
    return map(lambda x: x[0], res.fetchall())

def peers(c, nr):
    """ Returns a list of peers for AS nr """
    res = c.execute("""SELECT DISTINCT t_as FROM all_links
                       WHERE f_as = ? AND f_role = 'Peer'""",
                    (nr,))
    return map(lambda x: x[0], res.fetchall())

def customers(c, nr):
    """ Returns a list of customers for AS nr """
    res = c.execute("""SELECT DISTINCT t_as FROM all_links
                       WHERE f_as = ? AND f_role = 'Provider'""",
                    (nr,))
    return map(lambda x: x[0], res.fetchall())

def get_relationship(c, f, t):
    print (f, t)

    r = c.execute("""SELECT DISTINCT f_role || '-' || t_role FROM all_links
                        WHERE f_as = ? AND t_as = ?""", (f, t)).fetchall()

    print (r)
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

c = db.cursor()
print("Tier 1: {}".format(", ".join(map(str, get_tier1(c)))))
print("Tier 2: {}".format(", ".join(map(str, get_tier2(c)))))
print("Tier 3: {}".format(", ".join(map(str, get_tier3(c)))))

asnumbers = list(map(lambda x: x[0], db.cursor().execute("SELECT asnumber FROM asnumbers")))
for number in asnumbers:
    print("AS {}".format(number))
    print("    Providers: {}".format(", ".join(map(str, providers(c, number)))))
    print("    Peers: {}".format(", ".join(map(str, peers(c, number)))))
    print("    Customer: {}".format(", ".join(map(str, customers(c, number)))))

for number in asnumbers:
    res = c.execute("SELECT prefix, path FROM looking_glass WHERE asnumber = ?", (number,))
    for prefix, path in res.fetchall():
        # At the moment, ignore internal routes if the path is empty
        if str(number) == prefix[0]:
            if path != "":
                print("AS {} goes to {} via AS {}".format(number, prefix, path),
                        file=sys.stderr)
            continue

        # Check that the received paths are following Customer/Provider relationship
        state = "START"
        npath = str(number) + " " + str(path)
        npath = npath.split(" ")

        for f, t in zip(npath, npath[1:]):
            link = get_relationship(c, f, t)
            if state == "START":
                state = link
            elif state == "Customer-Provider":
                # Customer-Provider can go over a peer or an Provider-Customer
                state = link
            elif state == "Peer-Peer":
                if link != "Provider-Customer":
                    print("ERROR: AS {} has route to {} with path {} "
                            "contains {} link {} to {}".format(number, prefix,
                                path, link, f, t), file=sys.stderr)
            elif state == "Provider-Customer":
                if link != "Provider-Customer":
                    print("ERROR: AS {} has route to {} with path {} "
                            "contains {} link {} to {}".format(number, prefix,
                                path, link, f, t), file=sys.stderr)

    # Check that we receive from each customer routes to him and his customers
    for cs in customers(c, number):
        cset = set([cs])
        cset.update(recursive_customers(c, cs))

        for customer in cset:
            if not has_route_via(c, number, customer, cs):
                print("ERROR: AS {} should have an announcement for {} from AS {}".format(
                    number, "{}.0.0.0/8".format(customer), cs), file=sys.stderr)

    # Check that peers announce their customers and themself
    for pe in peers(c, number):
        pset = set([pe])
        pset.update(recursive_customers(c, pe))

        for customer in pset:
            if not has_route_via(c, number, customer, pe):
                print("ERROR: AS {} should have an announcement for {} from AS {}".format(
                    number, "{}.0.0.0/8".format(customer), pe), file=sys.stderr)

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
                print("ERROR: AS {} should have an announcement for {} from AS {}".format(
                    number, "{}.0.0.0/8".format(provider), pr), file=sys.stderr)

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

    relationship = get_relationship(c, number, nextas)

    # Sending traffic via customer is always good
    if relationship == "Provider-Customer":
        continue

    # relationship is Peer-Peer or Customer-Provider
    # so no theoretical route should exist via a customer
    for cs in customers(c, number):
        if theoretical_route_via(c, number, destination, cs):
            print("ERROR: AS {} is using {} to reach prefix {} via a {} relationship "
                    "although there is a Provider-Customer route via {}".format(
                        number, nextas, prefix, relationship, cs), file=sys.stderr)

    if relationship == "Peer-Peer":
        continue

    if relationship != "Customer-Provider":
        print("Expecting either Customer-Provider, Peer-Peer or Provider-Customer relationship",
                file=sys.stderr)
        raise AssertionError("Unexpected relationship")

    for pe in peers(c, number):
        if theoretical_route_via(c, number, destination, pe):
            print("ERROR: AS {} is using {} to reach prefix {} via a {} relationship "
                    "although there is a Peer-Peer route via {}".format(
                        number, nextas, prefix, relationship, pe), file=sys.stderr)

    #print("from {} to {} via {}".format(number, prefix, path))
