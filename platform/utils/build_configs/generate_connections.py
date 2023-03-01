"""This script generates the connections between the routers in the topology.

General layout: each area has two Tier1 ASes, and a number of transit ASes,
and two stub ASes. More in the wiki.
"""
import math


# Adjust parameters and where in the topology ASes are connected.
# ===============================================================

# Size of the topology.
# ---------------------

AREAS = 2
ASES_PER_AREA = 6
FIRST_IXP = 80

# Define the connections and roles of the ASes in each topology.
# --------------------------------------------------------------

default_link = ("100000", "300 ")  # throughput, delay
delay_link = ("100000", "1000")    # throughput, delay
customer = "Customer"
provider = "Provider"
peer = "Peer    "  # Spaces to align with the other roles in config file.

transit_as_topo = {
    # connection of AS to X: (AS city, AS role, link properties)
    # Example: The connection to the first provider is at Basel, and the AS
    # takes the role of a customer.
    # First provider is normal.
    'provider1': ('BASE', customer, default_link),
    'customer1': ('LAUS', provider, default_link),
    # Second one has a delayed link.
    'customer2': ('LUGA', provider, delay_link),
    'provider2': ('ZURI', customer, delay_link),
    # Peer and IXP.
    'peer': ('STGA', peer, default_link),
    'ixp': ('GENE', peer, default_link),
}

tier1_topo = {
    # Tier 1 Ases have no providers, but more peers and two IXPs.
    'ixp_central': ('STGA', peer, default_link),
    'ixp': ('GENE', peer, default_link),
    # Other Tier 1.
    'peer1': ('BASE', peer, default_link),
    'peer2': ('ZURI', peer, default_link),
    # Connections to customers.
    'customer1': ('LAUS', provider, default_link),
    'customer2': ('LUGA', provider, delay_link),  # Delayed link.
}

ixp_topo = {
    "as": ("None", peer, default_link),
}

stub_topo = transit_as_topo

# stub_topo = {
#     'ixp': 'BASE',
#     'peer': 'ZURI',
#     'customer1': 'ZURI',
#     'customer2': 'ZURI'
# }


# STEP 1: Enumerate the different ASes and IXPs and determine connections.
# ========================================================================

# Compute the different areas and IXPs.
# Ensure areas start at "nice" numbers, i.e. 1, 11, 21, etc.
_area_max = 10 * math.ceil((ASES_PER_AREA + 1) / 10)
transit = [
    list(range(_area_max*n + 1, _area_max*n + 1 + ASES_PER_AREA))
    for n in range(AREAS)
]

# IXPs
assert FIRST_IXP > max([max(_t) for _t in transit])
ixp_central = FIRST_IXP
# IXP between two areas each, so we need as many as areas.
ixp_out = list(range(FIRST_IXP + 1, FIRST_IXP + 1 + AREAS))

# STEP 2: Generate the connections.
# =================================

# First some helpers.
# Lookup tables for tier1, stub-ases and direct+indirect customers.
tier1 = [_t for _ts in transit for _t in _ts[:2]]
stub = [_t for _ts in transit for _t in _ts[-2:]]
customers = {
    asn: [
        _t for _t in _ts
        # Always pairs of two, one-based indexing; e.g., customers for 1&2 are
        # 3 and above, for 3 and 4 are 5 and above, etc.
        if _t > math.ceil(asn / 2) * 2
    ]
    for _ts in transit for asn in _ts
}

# Mapping of ASes to outer IXPs. (center IXP is connected only to Tier1.)
ixp_to_ases = {ixp: [] for ixp in ixp_out}
as_to_ixp = {}
for _i, _ts in enumerate(transit):
    left_ixp = ixp_out[_i]
    right_ixp = ixp_out[(_i + 1) % AREAS]  # Wrap around.

    left_ases = _ts[::2]
    right_ases = _ts[1::2]

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
    elif (asn == ixp_central) or (asn in ixp_out):
        return ixp_topo
    return transit_as_topo


def get_config(asn1, key1, asn2, key2, both_ways=False):
    """Return config lines.

    Returns both the "aslevel_links" and "aslevel_links_students" lines.
    If both_ways is True, also returns the reverse link for the
    aslevel_links_students.
    """
    subnet, ip1, ip2 = get_subnet_and_ips(asn1, asn2)
    city1, role1, link = get_topo(asn1)[key1]
    city2, role2, _ = get_topo(asn2)[key2]

    common_info = (asn1, city1, role1, asn2, city2, role2)
    common_info_rev = (asn2, city2, role2, asn1, city1, role1)

    # Last config entry is different for IXPs and ASes.
    if asn2 == ixp_central:
        # Central IXP is used by Tier1 to peer with each other.
        last_col = ",".join(map(str, tier1))
    elif asn2 in ixp_out:
        # Other IXPs are used by all ASes; they must not advertise to customers.
        last_col = ",".join([
            str(asn) for asn in ixp_to_ases[asn2]
            if (asn not in customers[asn1]) and (asn != asn1)
        ])
    else:  # non-IXP
        last_col = subnet

    if both_ways:
        return (
            # aslevel_links
            "\t".join(map(str, (*common_info, *link, last_col))),
            # aslevel_links_students line 1/2.
            (
                "\t".join(map(str, (*common_info, ip1))) + "\n" +
                "\t".join(map(str, (*common_info_rev, ip2)))
            ),
        )
    return (
        "\t".join(map(str, (*common_info, *link, last_col))),
        "\t".join(map(str, (*common_info, ip1))),
    )


config = []

for as_block in transit:
    for asn in as_block:
        # remember that ASes are in pairs of two.
        # 1, 3, ... are provider/customer 1 and
        # 2, 4, ... are provider/customer 2.
        asn_pos = 1 if asn % 2 else 2
        asn_partner = asn + 1 if asn % 2 else asn - 1
        asn_first = asn if asn % 2 else asn_partner

        # Providers. (not for Tier1, i.e. the first two ASes in each block)
        # ----------

        if not asn in tier1:
            provider1 = asn_first - 2
            provider2 = asn_first - 1
            label = f"customer{asn_pos}"  # 1 or 2.
            config.append(get_config(asn, "provider1", provider1, label))
            config.append(get_config(asn, "provider2", provider2, label))

        # Customers (not for stub ASes).
        # ----------

        if not asn in stub:
            customer1 = asn_first + 2
            customer2 = asn_first + 3
            label = f"provider{asn_pos}"  # 1 or 2.
            config.append(get_config(asn, "customer1", customer1, label))
            config.append(get_config(asn, "customer2", customer2, label))

        # Peers. (Tier 1 peers differently)
        # ------
        if not asn in tier1:
            config.append(get_config(asn, "peer", asn_partner, "peer"))
        else:
            # Peer with tier 1 in the same block and in the adjacent block.
            tier1_index = tier1.index(asn)
            peer1 = tier1[(tier1_index + 1) % len(tier1)]
            peer2 = tier1[(tier1_index - 1) % len(tier1)]
            config.append(get_config(asn, "peer1", peer1, "peer2"))
            config.append(get_config(asn, "peer2", peer2, "peer1"))

        # IXPs.
        # -----
        if asn in tier1:  # IXP central only for Tier1.
            # IXPs (add both directions to student config so they can see the
            # IXP ip address, too).
            config.append(
                get_config(asn, "ixp_central", ixp_central, "as", True)
            )

        config.append(get_config(asn, "ixp", as_to_ixp[asn], "as", True))


# STEP 2: Generate the config files.
# ==================================

config, student_config = zip(*config)

with open('aslevel_links.txt', 'w') as file:
    file.write("\n".join(config))

with open('aslevel_links_students.txt', 'w') as file:
    file.write("\n".join(student_config))
