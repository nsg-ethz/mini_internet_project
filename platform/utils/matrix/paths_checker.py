import time
import argparse
from get_paths import get_path_as

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
        print 'AS {}'.format(self.asn)
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
            print ('Path does not physically exist')
            wrong = True
            break

    return wrong

if __name__ == '__main__':

    parser = argparse.ArgumentParser()
    parser.add_argument('config_dir', type=str, default='../../config', help='Config directory')
    parser.add_argument('groups_dir', type=str, default='../../groups', help='Group directory generated at the mini-internet startup')
    parser.add_argument('outfile', type=str, default='paths_check.txt', help='File indicating whether path between pairs of ASes are valid')

    args = parser.parse_args()
    config_dir = args.config_dir
    groups_dir = args.groups_dir
    outfile = args.outfile

    dic_as = {}

    with open(config_dir+'/AS_config.txt', 'r') as fd:
        for line in fd.readlines():
            linetab = line.rstrip('\n').split('\t')
            asn = int(linetab[0])
            astype = linetab[1]
            
            new_as = AS(asn, astype)
            dic_as[asn] = new_as 

    with open(config_dir+'/external_links_config.txt', 'r') as fd:
        for line in fd.readlines():
            linetab = line.rstrip('\n').split('\t')
            as1n = int(linetab[0])
            as1t = linetab[2]
            as2n = int(linetab[3])
            as2t = linetab[5]

            if as1t == 'Peer':
                dic_as[as1n].peers_direct.add(dic_as[as2n])
            elif as1t == 'Provider':
                dic_as[as1n].customers_direct.add(dic_as[as2n])
            elif as1t == 'Customer':
                dic_as[as1n].providers_direct.add(dic_as[as2n])

            if as2t == 'Peer':
                dic_as[as2n].peers_direct.add(dic_as[as1n])
            elif as2t == 'Provider':
                dic_as[as2n].customers_direct.add(dic_as[as1n])
            elif as2t == 'Customer':
                dic_as[as2n].providers_direct.add(dic_as[as1n])

    # Populate the recursive set of customers, providers and peers for every AS
    for asn in dic_as:
        print (asn)
        dic_as[asn].compute_customers_rec()
        dic_as[asn].compute_providers_rec()
        dic_as[asn].compute_peers_rec()

        print (dic_as[asn])

    with open(outfile, 'w') as fd:
        for asn in dic_as:
            if dic_as[asn].type == 'AS':
                print asn
                path_to_as = get_path_as(config_dir, groups_dir, asn)

                for asdest in path_to_as:
                    paths_str = ''
                    status = 'Valid'
                    for path in path_to_as[asdest]:
                        if path == '':
                            path = []
                        else:
                            path = map(lambda x:int(x), path.split(' '))
                        if path_checker(dic_as, path):
                            status = 'Invalid'

                        print asn, asdest, path
                        paths_str += '-'.join(map(lambda x:str(x), path))+','

                    fd.write('{}\t{}\t{}\t{}\n'.format(asn, asdest, status, paths_str[:-1]))


    # print (path_checker(dic_as, [1,4,11,13,16]))