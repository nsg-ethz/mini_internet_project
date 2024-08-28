"""Check whether the path between ASes is correct.

Taken from https://github.com/nsg-ethz/mini_internet_project/tree/commnet-23/platform/docker_images/webserver/server/routing_project_server

Added a few functions at the bottom to parse the the generic rib instead of
`show ip bgp`.
"""

from collections import defaultdict
from typing import Dict


def check_connectivity(as_data, connectivity_data):
    """Check whether two ASes are reachable with ping."""
    # Build basic dict with all monitored connections.
    connected = {}
    for src_asn, src_data in as_data.items():
        if src_data["type"] != "AS":
            continue
        connected[src_asn] = {}
        for dst_asn, dst_data in as_data.items():
            if dst_data["type"] != "AS":
                continue
            connected[src_asn][dst_asn] = False

    # Check which connections we have data for.
    for src_asn, dst_asn, status in connectivity_data:
        connected[src_asn][dst_asn] = status

    return connected


def check_validity(as_data, connection_data, looking_glass_data):
    """Check if the paths between ASes are valid."""
    # Prepare AS objects.
    dic_as = {asn: AS(asn, data["type"]) for asn, data in as_data.items()}
    all_ases = set(dic_as.keys())

    # Add connections between them.
    for c1, c2 in connection_data:
        as1 = dic_as[c1["asn"]]
        as2 = dic_as[c2["asn"]]
        as1t = c1["role"]
        as2t = c2["role"]

        # Check role of AS2 to add appropriate connection to as 1.
        if as2t == "Peer":
            as1.peers_direct.add(as2)
        elif as2t == "Provider":
            as1.providers_direct.add(as2)
        elif as2t == "Customer":
            as1.customers_direct.add(as2)

        # And vice versa.
        if as1t == "Peer":
            as2.peers_direct.add(as1)
        elif as1t == "Provider":
            as2.providers_direct.add(as1)
        elif as1t == "Customer":
            as2.customers_direct.add(as1)

    # Populate the recursive set of customers, providers and peers for every AS
    for _as in dic_as.values():
        _as.compute_customers_rec()
        _as.compute_providers_rec()
        _as.compute_peers_rec()

    # check if another output format is better!
    results = defaultdict(dict)
    all_paths = get_all_paths_opt(looking_glass_data)
    for asn in dic_as:
        if dic_as[asn].type == "AS":
            if asn not in all_paths:
                # Bug in 2024: TA-AS looking glass data is not saved correctly.
                # Assume it's valid.
                for asdest in all_ases:
                    results[asn][asdest] = True
            else:
                paths = all_paths[asn]
                for asdest, asdestpaths in paths.items():
                    valid = True
                    for path in asdestpaths:
                        if path_checker(dic_as, path):
                            valid = False

                    results[asn][asdest] = valid

    return results


class AS:
    def __init__(self, asn, as_type):
        self.asn = asn
        self.customers_direct = set()
        self.peers_direct = set()
        self.providers_direct = set()
        self.type = as_type

        self.customers = set()
        self.peers = set()
        self.providers = set()

    def compute_customers_rec(self):
        cur_customers = list(self.customers_direct)
        while len(cur_customers) > 0:
            c = cur_customers.pop(0)
            cur_customers.extend(list(c.customers_direct))
            self.customers.add(c.asn)

    def compute_providers_rec(self):
        cur_providers = list(self.providers_direct)
        while len(cur_providers) > 0:
            c = cur_providers.pop(0)
            cur_providers.extend(list(c.providers_direct))
            self.providers.add(c.asn)

    # WARNING: must be executed the last, to take peers from IXP into account
    def compute_peers_rec(self):
        for peer in self.peers_direct:
            if peer.type == "IXP":
                for participant in peer.peers_direct:
                    if (
                        participant.asn not in self.providers
                        and participant.asn not in self.customers
                        and participant.asn != self.asn
                    ):
                        self.peers.add(participant.asn)
            elif peer.type == "AS":
                self.peers.add(peer.asn)

    def __str__(self):
        print("AS {}".format(self.asn))
        cs = "Customers: "
        for cus in self.customers:
            cs += str(cus) + ","
        cs = cs[:-1]

        ps = "Providers: "
        for prs in self.providers:
            ps += str(prs) + ","
        ps = ps[:-1]

        pe = "Peers: "
        for pes in self.peers:
            pe += str(pes) + ","
        pe = pe[:-1]

        return cs + "\n" + ps + "\n" + pe


def path_checker(dic_as, aspath):
    """Check if the path is valid."""
    # Ignore repeated ASes, e.g. path prepending.
    # The following works becauuse python dicts guarantee ordered keys.
    aspath = list(dict.fromkeys(aspath))

    if len(aspath) <= 1:
        return False

    # Status can be: None (at first), Up, Flat, Down
    if aspath[1] in dic_as[aspath[0]].providers:
        status = "UP"
    elif aspath[1] in dic_as[aspath[0]].customers:
        status = "DOWN"
    elif aspath[1] in dic_as[aspath[0]].peers:
        status = "FLAT"

    wrong = False
    for i in range(1, len(aspath) - 1):
        if aspath[i + 1] in dic_as[aspath[i]].providers:
            if status == "DOWN" or status == "FLAT":
                wrong = True
                break
            else:
                status = "UP"
        elif aspath[i + 1] in dic_as[aspath[i]].customers:
            status = "DOWN"
        elif aspath[i + 1] in dic_as[aspath[i]].peers:
            if status == "DOWN" or status == "FLAT":
                wrong = True
                break
            else:
                status = "FLAT"
        else:
            print("Path does not physically exist")
            print(aspath)
            wrong = True
            break

    return wrong


# Old logic from show ip bgp (with path)

# def get_path_to_as(asn: int,
#                    as_data: Dict[int, Dict],
#                    looking_glass_data: Dict[int, Dict[str, Dict]]):
#     """Return the path to as."""
#     routers = as_data[asn]['routers']
#     path_to_as = {}
#     for router in routers:
#         router_bgp = looking_glass_data[asn][router]
#         tmp = get_path_from_router(router_bgp)
#         for asdest in tmp:
#             if asdest not in path_to_as:
#                 path_to_as[asdest] = set()
#             path_to_as[asdest] = path_to_as[asdest].union(set(tmp[asdest]))

#     return path_to_as


# def get_path_from_router(router_bgp_data):
#     path_to_as = {}

#     # TODO: needed to remove this, the config contains directly the routes.
#     # BGP is not running in the router
#     # if 'localAS' not in router_bgp_data:
#     #     return path_to_as

#     # local_as = router_bgp_data['localAS']
#     for prefix in router_bgp_data:
#         for route_pref in router_bgp_data[prefix]:
#             breakpoint()
#             aspath = route_pref['path']
#             asdest = int(prefix.split('.')[0])

#             # if bestpath:
#             if asdest not in path_to_as:
#                 path_to_as[asdest] = []
#             path_to_as[asdest].append(aspath)

#     return path_to_as


# This part is new (from show ip route (without path))


def get_paths_from_as(looking_glass_data, from_as):
    """Get all paths from from_as to each other AS."""
    next_ases = {
        int(prefix.split(".")[0])
        for rib in looking_glass_data[int(from_as)].values()
        for prefix in rib
    }
    return {
        to_as: get_paths(looking_glass_data, int(from_as), to_as) for to_as in next_ases
    }


def get_paths(looking_glass_data, from_as: int, to_as: int, prev_path=tuple()):
    """Get paths from from_as to to_as."""
    path = (*prev_path, from_as)
    # Loop prevention: if from_as is already in path, return the invalid path
    # (path checker can mark this later) and stop.
    if from_as in prev_path:
        # TODO: This is not _quite_ how BGP would return it.
        return {
            path,
        }

    def _get_next_as(ip, ixp_first=180, ext_first=179):
        """Return next hop AS.

        If the first byte is 180, it is an IXP, next hop last byte.
        If the first byte is 179, from and next are middle two bytes.
        Otherwise, next is the first byte.
        """
        first, second, third, last = map(int, ip.split("."))
        if first == ixp_first:
            return last
        elif first == ext_first:
            return second if second != from_as else third
        return first

    def _internal(nexthop):
        return ("ip" in nexthop) and (int(nexthop["ip"].split(".")[0]) == from_as)

    # The _ultimate_ loop.
    # Go over all routers, each entry for a prefix, and each nexthop.
    # No nexthop ip -> directly connected.
    nexthops = {
        _get_next_as(nexthop["ip"]) if "ip" in nexthop else None
        for rib in looking_glass_data[from_as].values()
        for prefix, data in rib.items()
        if int(prefix.split(".")[0]) == to_as
        for entry in data
        for nexthop in entry["nexthops"]
        if not _internal(nexthop)
    }
    if not nexthops:
        if not prev_path:
            return set()  # No paths at all to the destination
        if from_as == 51:
            return set()  # in 2023, we are missing some data from TA-AS 51.
        # If there is a previous path, this means we got routed here but there
        # is actually no path, this should never occur.
        # (The students should not set up static routes to other ASes)
        raise RuntimeError(f"Path {path} to {to_as} is dead.")

    # Recursion
    new_paths = {
        path_from_nexthop
        for nexthop in nexthops
        if nexthop is not None  # ignore local
        for path_from_nexthop in get_paths(
            looking_glass_data, nexthop, to_as, prev_path=path
        )
    }
    # Local path, if any
    if any(nexthop is None for nexthop in nexthops):
        new_paths.add(path)

    return new_paths


# Optimized
def get_all_paths_opt(looking_glass_data):
    """Get all paths from each AS to each other AS."""

    def _get_next_as(ip, from_as, ixp_first=180, ext_first=179):
        """Return next hop AS.

        If the first byte is 180, it is an IXP, next hop last byte.
        If the first byte is 179, from and next are middle two bytes.
        Otherwise, next is the first byte.
        """
        first, second, third, last = map(int, ip.split("."))
        if first == ixp_first:
            return last
        elif first == ext_first:
            return second if second != from_as else third
        return first

    # First get all nexthops, None if it terminates.
    all_nexthops = {}  # (from, to) -> nexthop
    for from_as, routers in looking_glass_data.items():
        for rib in routers.values():
            for prefix, data in rib.items():
                to_as = int(prefix.split(".")[0])
                current_nexthops = all_nexthops.setdefault((from_as, to_as), set())
                for entry in data:
                    for nexthop in entry["nexthops"]:
                        if "ip" not in nexthop:
                            # Directly connected, path ends here.
                            pass
                            # current_nexthops.add(None)
                        elif int(nexthop["ip"].split(".")[0]) != from_as:
                            current_nexthops.add(_get_next_as(nexthop["ip"], from_as))
                            # Not towards another internal router. Add.

    # Now initialize current paths from nexthops and iterate until all paths
    # are terminated.
    current_paths = {
        (from_as, to_as): {
            (
                from_as,
                nh,
            )
            for nh in v
        }
        for (from_as, to_as), v in all_nexthops.items()
    }
    results = {}
    # Results needs to be 2-d instead of flat.
    for from_as, to_as in current_paths:
        results.setdefault(from_as, {}).setdefault(to_as, set())
    while current_paths:
        remaining_paths = {k: set() for k in current_paths}
        for (from_as, to_as), paths in current_paths.items():
            # If there are no paths, terminate at `from_as`
            if not paths:
                results[from_as][to_as].add((from_as,))
            for path in paths:
                # Get nexthop from last hop in current path.
                nexthops = all_nexthops.get((path[-1], to_as), set())
                if not nexthops:
                    results[from_as][to_as].add(path)  # Terminate
                for nexthop in nexthops:
                    if nexthop in path:  # Loop; terminate
                        results[from_as][to_as].add(path)
                    else:
                        # Otherwise, add to remaining paths and keep going.
                        remaining_paths[(from_as, to_as)].add((*path, nexthop))
        # Update state, remove empty paths to not iterate infinitely.
        current_paths = {k: v for k, v in remaining_paths.items() if v}

    return results
