#!/usr/bin/env python3

"""This script generates the connections between the routers in the topology.

Create four files:
- AS_config.txt: which config files to use for each AS and whether to
    auto-configure.
- aslevel_links.txt: which ASes are connected to which ASes and how.
- aslevel_links_students.txt: same as above, but with concrete IP addresses,
    meant as a lookup for students. Read by the webserver.
- hijack_config.txt: ASes that try to hijack prefixes for the RPKI task.

General layout:
- Areas with two "columns" of ASes.
- ASes in the same row are peers, ASes in the row above are providers,
    ASes in the row below are customers.
- Consquently, each area has two Tier1 ASes, and two stub ASes.
- The areas are arranged in a circle, and between two neighboring areas there
    is an IXP.
- A central IXP connects all Tier1 ASes and additionally, the Tier1 ASes also
    peer with the tier1 in the adjacent area. That is, the Tier1 is a ring of
    peers with a central IXP in the middle, such that each Tier1 can peer with
    all other Tier1s.
- The two stub ASes in each area try to hijack each others prefixes.
- To configuration easier, students do not control:
    - The Tier1 ASes.
    - The stub ASes.
    - The IXPs.
    - The ASes adjacent to the hijacking ASes (they are a buffer).
- This means that each area has an overhead of 6 ASes: 2 Tier 1, 2 stub,
    2 buffer.

You can disable the stub hijacks by setting ENABLE_STUB_HIJACKS to False.
If you disable the hijacks, there will also be no buffer ASes, and each area
only has an overhead of 4 ASes (2 Tier 1, 2 stub).

!IMPORTANT!
For the stub hijack to work properly, there are some conditions on the network
topology: conrerely, the routers connected to the IXP and peer **must not** be
on the path between MEASURMENT and any provider or the measurement target.
Otherwise, unintended traffic will get blackholed.

Important to consider: the config file configures _both_ ends of the connection,
so we need to ensure that we only have one config line for each two endpoints.
Concretely, we define config only for providers, not for customers, and only
for the peer on the "left" in the topology.
"""

import math


# Adjust parameters and where in the topology ASes are connected.
# ===============================================================

# General settings.
# -----------------

# If true, stub ASes in the same area try to hijack each others prefixes. Also,
# add two TA-configured ASes between the stubs and student ASes so that no
# student AS is directly connected to a malicious AS.
ENABLE_STUB_HIJACKS = False

# Set true to test the topology.
AUTOCONF_EVERYTHING = False

# If true, links between student ASes are only assigned a subnet in the
# aslevel_links_students.txt file. If False, they are assigned an IP address.
SUBNETS_ONLY_FOR_STUDENTS = True

# If true, the buffer (or stub, if no hijacks) ASes advertise their prefix to
# the same region via the IXP, so the students can better debug denying those
# advertisements.
BUFFER_ADVERTISES_ALL_VIA_IXP = True

# Size of the topology.
# ---------------------

AREAS = 2
CONFIGURABLE_PER_AREA = 2  # Number of ASes that can be configured by students.
FIRST_IXP = 80

# Define the connections and roles of the ASes in each topology.
# --------------------------------------------------------------

skip_groups = [
    127,
]  # 127 is a reserved IP range, cannot use as AS prefix.
do_not_hijack = [
    1,
]  # AS 1 hosts krill, so we need it reachable.

default_link = ("1mbit", "2.5ms", "50ms")  # throughput, delay, buffer,
delay_link = ("1mbit", "25ms ", "50ms")  # as above; not used by default
customer = "Customer"
provider = "Provider"
peer = "Peer    "  # Spaces to align with the other roles in config file.

transit_as_topo = {
    # connection of AS to X: (AS city, AS role)
    # Example: The connection to the first provider is at Basel, and the AS
    # takes the role of a customer.
    'provider1': ('MUNI', customer),
    'provider2': ('BASE', customer),
    'customer1': ('LYON', provider),
    'customer2': ('MILA', provider),
    # Peer and IXP.
    'peer': ('LUGA', peer),
    'ixp': ('VIEN', peer),
}

# All non-transit ASes only have a single router ZURI.

tier1_topo = {
    # Tier 1 Ases have no providers, but more peers and two IXPs.
    'ixp_central': ('ZURI', peer),
    'ixp': ('ZURI', peer),
    # Other Tier 1.
    'peer1': ('ZURI', peer),
    'peer2': ('ZURI', peer),
    # Connections to customers.
    'customer1': ('ZURI', provider),
    'customer2': ('ZURI', provider),
}

# We use a minimal stub topo without hijacks, and the transit one with hijacks.
stub_topo = transit_as_topo if ENABLE_STUB_HIJACKS else {
    # Same providers, but IXP and peer. are somewhere else.
    "provider1": ("ZURI", customer),
    "provider2": ("ZURI", customer),
    "peer": ("ZURI", peer),
    "ixp": ("ZURI", peer),
}

buffer_topo = {
    # Looks like transit AS, but we only have a single router.
    "provider1": ("ZURI", customer),
    "provider2": ("ZURI", customer),
    "customer1": ("ZURI", provider),
    "customer2": ("ZURI", provider),
    "peer": ("ZURI", peer),
    "ixp": ("ZURI", peer),
}

ixp_topo = {
    "as": ("None", peer),
}

def get_link(role1, role2):
    """Here, you can define the link properties between neighbors."""
    #return default_link
    # Alternative:
    # In this version, we slow down the link to the provider in the other
    # column, e.g. between 1 and 3, and between 2 and 4; but not the links in
    # the same, e.g. 1 and 4, and 2 and 3.
    #
    nodes = set([role1, role2])
    delayed = [
        # "left" ASes
        {'provider1', 'customer2'},
        # "right" ASes
        {'provider2', 'customer1'},
    ]
    return delay_link if nodes in delayed else default_link


# DONE. You should not need to change anything below this line.
# ============================================================


# STEP 1: Enumerate the different ASes and IXPs and determine connections.
# ========================================================================

# Compute the different areas and IXPs.
# Ensure areas start at "nice" numbers, i.e. 1, 11, 21, etc.
assert AREAS >= 2, "Need at least two areas."
assert CONFIGURABLE_PER_AREA % 2 == 0, "Must be even."
ASES_PER_AREA = CONFIGURABLE_PER_AREA + 4  # 2 stub, 2 provider
if ENABLE_STUB_HIJACKS:
    ASES_PER_AREA += 2  # add 2 ASes as buffer between students and hijackers.
# Leave enough space if we have to skip some ASes.
_area_max = 10 * math.ceil((ASES_PER_AREA + 1 + len(skip_groups)) / 10)


def _area_ases(start):
    """Append ASes to the list, skipping the ones in skip_groups."""
    _ases = []
    while len(_ases) < ASES_PER_AREA:
        if start not in skip_groups:
            _ases.append(start)
        start += 1
    return _ases


areas = [_area_ases(_area_max * n + 1) for n in range(AREAS)]

# IXPs
highest_as = max([max(area) for area in areas])
assert FIRST_IXP > highest_as, f"IXP must be above {highest_as}"
ixp_central = FIRST_IXP
# IXP between two areas each, so we need as many as areas.
ixp_out = list(range(FIRST_IXP + 1, FIRST_IXP + 1 + AREAS))

# STEP 2: Generate the connections.
# =================================

# First some helpers.
# Lookup tables for tier1, stub-ases and direct+indirect customers.
tier1 = [asn for area in areas for asn in area[:2]]
stub = [asn for area in areas for asn in area[-2:]]
# buffer to hijacking stubs
if ENABLE_STUB_HIJACKS:
    buffer = [asn for area in areas for asn in area[-4:-2]]
else:
    buffer = []

# Mapping of ASes to outer IXPs. (center IXP is connected only to Tier1.)
ixp_to_ases = {ixp: [] for ixp in ixp_out}
as_to_ixp = {}
for _i, area in enumerate(areas):
    left_ixp = ixp_out[_i]
    right_ixp = ixp_out[(_i + 1) % AREAS]  # Wrap around.

    left_ases = area[::2]
    right_ases = area[1::2]

    ixp_to_ases[left_ixp] += left_ases
    ixp_to_ases[right_ixp] += right_ases
    for _a in left_ases:
        as_to_ixp[_a] = left_ixp
    for _a in right_ases:
        as_to_ixp[_a] = right_ixp


def get_subnet_and_ips(asn1, asn2):
    """Generate the subnet, which follows the following pattern:

    If both ASes are not IXPs:

        Subnet:  179.<smaller asn>.<larger asn>.0/24
        IP ASN1: 179.<smaller asn>.<larger asn>.<asn1>/24
        IP ASN2: 179.<smaller asn>.<larger asn>.<asn2>/24

    If AS 2 is an IXP:

        Subnet:  180.<ixp>.0.0/24
        IP ASN1: 180.<ixp>.0.<asn1>/24
        IP IXP: 180.<ixp>.0.<ixp>/24
    """
    if (asn2 == ixp_central) or (asn2 in ixp_out):
        ixp = asn2
        return (
            f"180.{ixp}.0.0/24",
            f"180.{ixp}.0.{asn1}/24",
            f"180.{ixp}.0.{ixp}/24",
        )

    _middle_octets = f"{min(asn1, asn2)}.{max(asn1, asn2)}"
    return (
        f"179.{_middle_octets}.0/24",
        f"179.{_middle_octets}.{asn1}/24",
        f"179.{_middle_octets}.{asn2}/24",
    )


def get_topo(asn):
    """Return relevant topology."""
    if asn in tier1:
        return tier1_topo
    elif asn in stub:
        return stub_topo
    elif asn in buffer:
        return buffer_topo
    elif (asn == ixp_central) or (asn in ixp_out):
        return ixp_topo
    return transit_as_topo


def get_config(asn1, key1, asn2, key2):
    """Return config lines.

    Returns both the "aslevel_links" and "aslevel_links_students" lines.

    For the student config, always return both directions.
    """
    subnet, ip1, ip2 = get_subnet_and_ips(asn1, asn2)
    city1, role1 = get_topo(asn1)[key1]
    city2, role2 = get_topo(asn2)[key2]
    link = get_link(key1, key2)

    as_info = (asn1, city1, role1, asn2, city2, role2)
    as_info_rev = (asn2, city2, role2, asn1, city1, role1)

    # Last config entry is different for IXPs and ASes.
    if asn2 == ixp_central:
        # Central IXP is used by Tier1 to peer with each other.
        last_col = ",".join(map(str, tier1))
    elif asn2 in ixp_out:
        # Other IXPs are used by all ASes;
        # they must not advertise to customers or providers, as this would
        # go against business relationships.
        # Concretely, do not advertise to same area.
        # The buffer ASes do _not_ follow this rule and advertise to their own
        # area so that the students can debug denying those.
        # If there are no buffer ASes, the stub ASes are used instead.
        advertise_too_much = []
        if BUFFER_ADVERTISES_ALL_VIA_IXP:
            if buffer:
                advertise_too_much = buffer
            else:
                advertise_too_much = stub

        asn1_area = next(area for area in areas if asn1 in area)
        last_col = ",".join(
            [
                str(asn)
                for asn in ixp_to_ases[asn2]
                if (
                    (asn not in asn1_area)
                    or ((asn1 in advertise_too_much) and (asn != asn1))
                )
            ]
        )
    else:  # non-IXP
        last_col = subnet

    # If both ASes are student ASes, only return subnets;
    # student should discuss IP addresses!
    if SUBNETS_ONLY_FOR_STUDENTS and is_student(asn1) and is_student(asn2):
        ip1 = ip2 = subnet

    return (
        # aslevel_links
        "\t".join(map(str, (*as_info, *link, last_col))),
        # aslevel_links_students line 1/2.
        (
            "\t".join(map(str, (*as_info, ip1)))
            + "\n"
            + "\t".join(map(str, (*as_info_rev, ip2)))
        ),
    )


def is_student(asn):
    """Return True if the AS is a (potential) student AS."""
    return not any(
        (
            # All the following are TA-managed.
            asn in tier1,
            asn in buffer,
            asn in stub,
            asn in ixp_out,
            asn == ixp_central,
        )
    )


config = []

for as_block in areas:
    for idx, asn in enumerate(as_block):
        # remember that ASes are in pairs of two.
        # 1, 3, ... are provider/customer 1 and
        # 2, 4, ... are provider/customer 2.
        asn_pos = 2 if idx % 2 else 1
        asn_partner = as_block[idx - 1 if idx % 2 else idx + 1]
        first_idx = idx - 1 if idx % 2 else idx

        # Not needed -> one-directional only for AS_level config.
        # # Providers. (not for Tier1, i.e. the first two ASes in each block)
        # # ----------

        # if not asn in tier1:
        #     provider1 = asn_first - 2
        #     provider2 = asn_first - 1
        #     label = f"customer{asn_pos}"  # 1 or 2.
        #     # None for AS config.
        #     config.append(
        #         (None, get_config(asn, "provider1", provider1, label)[1]))
        #     config.append(
        #         (None, get_config(asn, "provider2", provider2, label)[1]))

        # Customers (not for stub ASes).
        # ----------

        if asn not in stub:
            customer1 = as_block[first_idx + 2]
            customer2 = as_block[first_idx + 3]
            label = f"provider{asn_pos}"  # 1 or 2.
            config.append(get_config(asn, "customer1", customer1, label))
            config.append(get_config(asn, "customer2", customer2, label))

        # Peers. (Tier 1 peers differently)
        # ------
        if asn not in tier1:
            # Only for the "left" AS.
            if (idx % 2) == 0:
                config.append(get_config(asn, "peer", asn_partner, "peer"))
        else:
            # Peer with tier 1 in the same block and in the adjacent block.
            tier1_index = tier1.index(asn)
            peer1 = tier1[(tier1_index + 1) % len(tier1)]
            config.append(get_config(asn, "peer1", peer1, "peer2"))
            # Do not peer with the previous AS.
            # peer2 = tier1[(tier1_index - 1) % len(tier1)]
            # config.append(get_config(asn, "peer2", peer2, "peer1"))

        # IXPs.
        # -----
        if asn in tier1:  # IXP central only for Tier1.
            # IXPs (add both directions to student config so they can see the
            # IXP ip address, too).
            config.append(get_config(asn, "ixp_central", ixp_central, "as"))

        config.append(get_config(asn, "ixp", as_to_ixp[asn], "as"))


# STEP 2: Generate the config files.
# ==================================

config, student_config = zip(*config)

# assume the script is run from the platform directory
aslevel_link_file = "./config/aslevel_links.txt"
with open(aslevel_link_file, "w") as file:
    file.write("\n".join([line for line in config if line is not None]))

aslevel_link_students_file = "./config/aslevel_links_students.txt"
with open(aslevel_link_students_file, "w") as file:
    file.write("\n".join([line for line in student_config if line is not None]))


# STEP 3: Generate the file with contains which configs to use.
# =============================================================

as_config_file = "./config/AS_config.txt"
with open(as_config_file, "w") as fd:
    if ENABLE_STUB_HIJACKS:
        # Need the full topology in the stub for the hijack
        small_config = (tier1 + buffer)
    else:
        small_config = (tier1 + stub + buffer)

    for area in areas:
        for asn in area:
            if asn == 1:  # By default we set krill in AS1
                fd.write(
                    f"{asn}\tAS\tConfig  \tl3_routers_krill.txt\t"
                    "l3_links_krill.txt\tempty.txt\tempty.txt\t"
                    "empty.txt\n"
                )
            elif asn in small_config:
                fd.write(
                    f"{asn}\tAS\tConfig  \tl3_routers_tier1_and_stub.txt\t"
                    "l3_links_tier1_and_stub.txt\tempty.txt\tempty.txt\t"
                    "empty.txt\n"
                )
            else:  # "Normal" ASes.
                if AUTOCONF_EVERYTHING or asn in (buffer + stub):
                    conf = "Config  "
                else:
                    conf = "NoConfig"
                fd.write(
                    f"{asn}\tAS\t{conf}\tl3_routers.txt\t"
                    "l3_links.txt\tl2_switches.txt\tl2_hosts.txt\t"
                    "l2_links.txt\n"
                )
    for asn in [ixp_central, *ixp_out]:
        fd.write(f"{asn}\tIXP\tConfig  \tN/A\tN/A\tN/A\tN/A\tN/A\n")


# STEP 4: Specify hijacks.
# ========================
# Currently, stub ASes try to hijack each other, but only for ASes in the same
# area to limit the "blast radius".

hijacks = []
if ENABLE_STUB_HIJACKS:
    for asn in stub:
        # Towards other ASes in the same area _and_ connected to the same IXP,
        # we hijack the other stub AS in the same area via the IXP.
        asn_area = next(area for area in areas if asn in area)
        asn_ixp = as_to_ixp[asn]
        victim = next(asn2 for asn2 in stub if (asn2 != asn) and (asn2 in asn_area))
        other_ases = [
            asn2
            for asn2 in asn_area
            if (asn2 != asn)
            and (asn2 in ixp_to_ases[asn_ixp])
            and (asn2 not in do_not_hijack)
        ]

        node_towards_victim, *_ = stub_topo["peer"]
        node_towards_ixp, *_ = stub_topo["ixp"]
        hijacks.append(
            (
                asn,
                victim,
                ",".join(map(str, other_ases)),
                asn_ixp,
                node_towards_victim,
                node_towards_ixp,
            )
        )

with open("./config/hijacks.txt", "w") as file:
    for hijack in hijacks:
        file.write("\t".join(map(str, hijack)) + "\n")
