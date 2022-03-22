"""Check whether the path between ASes is correct."""

from collections import defaultdict
from typing import Dict


def check_connectivity(as_data, connectivity_data):
    """Check whether two ASes are reachable with ping."""
    # Build basic dict with all monitored connections.
    connected = {}
    for src_asn, src_data in as_data.items():
        if src_data['type'] != 'AS':
            continue
        connected[src_asn] = {}
        for dst_asn, dst_data in as_data.items():
            if dst_data['type'] != 'AS':
                continue
            connected[src_asn][dst_asn] = False

    # Check which connections we have data for.
    for src_asn, dst_asn, status in connectivity_data:
        connected[src_asn][dst_asn] = status

    return connected


def check_validity(as_data, connection_data, looking_glass_data):
    """Check if the paths between ASes are valid."""
    # Prepare AS objects.
    dic_as = {asn: AS(asn, data['type']) for asn, data in as_data.items()}

    # Add connections between them.
    for c1, c2 in connection_data:
        as1 = dic_as[c1['asn']]
        as2 = dic_as[c2['asn']]
        as1t = c1['role']
        as2t = c2['role']

        # Check role of AS2 to add appropriate connection to as 1.
        if as2t == 'Peer':
            as1.peers_direct.add(as2)
        elif as2t == 'Provider':
            as1.providers_direct.add(as2)
        elif as2t == 'Customer':
            as1.customers_direct.add(as2)

        # And vice versa.
        if as1t == 'Peer':
            as2.peers_direct.add(as1)
        elif as1t == 'Provider':
            as2.providers_direct.add(as1)
        elif as1t == 'Customer':
            as2.customers_direct.add(as1)

    # Populate the recursive set of customers, providers and peers for every AS
    for _as in dic_as.values():
        _as.compute_customers_rec()
        _as.compute_providers_rec()
        _as.compute_peers_rec()

    # check if another ooutput format is better!
    results = defaultdict(dict)
    for asn in dic_as:
        if dic_as[asn].type == 'AS':
            path_to_as = get_path_to_as(asn, as_data, looking_glass_data)

            for asdest in path_to_as:
                paths_str = ''
                valid = True
                for path in path_to_as[asdest]:
                    if path == '':
                        path = []
                    else:
                        path = list(map(int, path.split(' ')))
                    if path_checker(dic_as, path):
                        valid = False

                    paths_str += '-'.join(map(lambda x: str(x), path))+','

                results[asn][asdest] = valid
                #results.append((asn, asdest, status, paths_str[:-1]))

    return(results)


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
            if peer.type == 'IXP':
                for participant in peer.peers_direct:
                    if participant.asn not in self.providers and participant.asn not in self.customers and participant.asn != self.asn:
                        self.peers.add(participant.asn)
            elif peer.type == 'AS':
                self.peers.add(peer.asn)

    def __str__(self):
        print('AS {}'.format(self.asn))
        cs = 'Customers: '
        for cus in self.customers:
            cs += str(cus)+','
        cs = cs[:-1]

        ps = 'Providers: '
        for prs in self.providers:
            ps += str(prs)+','
        ps = ps[:-1]

        pe = 'Peers: '
        for pes in self.peers:
            pe += str(pes)+','
        pe = pe[:-1]

        return cs+'\n'+ps+'\n'+pe


def path_checker(dic_as, aspath):

    if len(aspath) <= 1:
        return False

    # Status can be: None (at first), Up, Flat, Down
    if aspath[1] in dic_as[aspath[0]].providers:
        status = 'UP'
    elif aspath[1] in dic_as[aspath[0]].customers:
        status = 'DOWN'
    elif aspath[1] in dic_as[aspath[0]].peers:
        status = 'FLAT'

    wrong = False
    for i in range(1, len(aspath)-1):
        if aspath[i+1] in dic_as[aspath[i]].providers:
            if status == 'DOWN' or status == 'FLAT':
                wrong = True
                break
            else:
                status = 'UP'
        elif aspath[i+1] in dic_as[aspath[i]].customers:
            status = 'DOWN'
        elif aspath[i+1] in dic_as[aspath[i]].peers:
            if status == 'DOWN' or status == 'FLAT':
                wrong = True
                break
            else:
                status = 'FLAT'
        else:
            print('Path does not physically exist')
            wrong = True
            break

    return wrong


def get_path_to_as(asn: int,
                   as_data: Dict[int, Dict],
                   looking_glass_data: Dict[int, Dict[str, Dict]]):
    """Return the path to as."""
    routers = as_data[asn]['routers']
    path_to_as = {}
    for router in routers:
        router_bgp = looking_glass_data[asn][router]
        tmp = get_path_from_router(router_bgp)
        for asdest in tmp:
            if asdest not in path_to_as:
                path_to_as[asdest] = set()
            path_to_as[asdest] = path_to_as[asdest].union(set(tmp[asdest]))

    return path_to_as


def get_path_from_router(router_bgp_data):
    path_to_as = {}

    # BGP is not running in the router
    if 'localAS' not in router_bgp_data:
        return path_to_as

    local_as = router_bgp_data['localAS']
    for prefix in router_bgp_data['routes']:
        for route_pref in router_bgp_data['routes'][prefix]:
            aspath = route_pref['path']
            asdest = int(prefix.split('.')[0])

            # if bestpath:
            if asdest not in path_to_as:
                path_to_as[asdest] = []
            path_to_as[asdest].append(aspath)

    return path_to_as
