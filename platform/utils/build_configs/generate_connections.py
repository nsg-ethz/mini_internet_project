from netaddr import *
import random
import string

# Pick the size of the topology that you want.
# The Topology will always follow the same pattern, with different regions, Tier1, Stub and transit.
# Two ASes in every raw in a region. One central IXP and one between each neighboring region.
NB_ASES = 12

if NB_ASES == 12:
    # 12 ASes
    tier1 = [[1,2],[11,12]]
    transit = [[1,2,3,4,5,6],[11,12,13,14,15,16]]
    ixp_central = 80
    ixp_out = [81,82]
elif NB_ASES == 20:
    # 20 ASes
    tier1 = [[1,2],[11,12]]
    transit = [[1,2,3,4,5,6,7,8,9,10],[11,12,13,14,15,16,17,18,19,20]]
    ixp_central = 80
    ixp_out = [81,82]
elif NB_ASES == 30:
    # 30 ASes
    tier1 = [[1,2],[11,12],[21,22]]
    transit = [[1,2,3,4,5,6,7,8,9,10],[11,12,13,14,15,16,17,18,19,20],[21,22,23,24,25,26,27,28,29,30]]
    ixp_central = 80
    ixp_out = [81,82,83]
elif NB_ASES == 40:
    # 40 ASes
    tier1 = [[1,2],[11,12],[21,22],[31,32]]
    transit = [[1,2,3,4,5,6,7,8,9,10],[11,12,13,14,15,16,17,18,19,20],[21,22,23,24,25,26,27,28,29,30], [31,32,33,34,35,36,37,38,39,40]]
    ixp_central = 80
    ixp_out = [81,82,83,84]
elif NB_ASES == 60:
    # 60 ASes
    tier1 = [[1,2],[11,12],[21,22],[31,32],[41,42],[51,52]]
    transit = [[1,2,3,4,5,6,7,8,9,10],[11,12,13,14,15,16,17,18,19,20],[21,22,23,24,25,26,27,28,29,30], \
    [31,32,33,34,35,36,37,38,39,40],[41,42,43,44,45,46,47,48,49,50],[51,52,53,54,55,56,57,58,59,60]]
    ixp_central = 80
    ixp_out = [81,82,83,84,85,86]
elif NB_ASES == 72:
    # 72 ASes
    tier1 = [[1,2],[21,22],[41,42],[61,62],[81,82],[101,102]]
    transit = [[1,2,3,4,5,6,7,8,9,10,11,12],[21,22,23,24,25,26,27,28,29,30,31,32], \
    [41,42,43,44,45,46,47,48,49,50,51,52], [61,62,63,64,65,66,67,68,69,70,71,72], \
    [81,82,83,84,85,86,87,88,89,90,91,92],[101,102,103,104,105,106,107,108,109,110,111,112]]
    ixp_central = 120
    ixp_out = [121,122,123,124,125,126]
elif NB_ASES == 76:
    # 76 ASes
    tier1 = [[1,2],[21,22],[41,42],[61,62],[81,82],[101,102]]
    transit = [[1,2,3,4,5,6,7,8,9,10,11,12,13,14],[21,22,23,24,25,26,27,28,29,30,31,32], \
    [41,42,43,44,45,46,47,48,49,50,51,52,53,54], [61,62,63,64,65,66,67,68,69,70,71,72], \
    [81,82,83,84,85,86,87,88,89,90,91,92],[101,102,103,104,105,106,107,108,109,110,111,112]]
    ixp_central = 120
    ixp_out = [121,122,123,124,125,126]
elif NB_ASES == 70:
    # 78 ASes
    tier1 = [[1,2],[21,22],[41,42],[61,62],[81,82],[101,102]]
    transit = [[1,2,3,4,5,6,7,8,9,10,11,12,13,14],[21,22,23,24,25,26,27,28,29,30,31,32,33,34], \
    [41,42,43,44,45,46,47,48,49,50,51,52,53,54], [61,62,63,64,65,66,67,68,69,70,71,72], \
    [81,82,83,84,85,86,87,88,89,90,91,92],[101,102,103,104,105,106,107,108,109,110,111,112]]
    ixp_central = 120
    ixp_out = [121,122,123,124,125,126]



# Description of the routers used for every connection.
# We differentiate between Transit, Tier1 and Stub ASes
transit_as_topo = {
    'provider1': 'LYON',
    'provider2': 'MILA',
    'customer1': 'MUNI',
    'customer2': 'BASE',
    'peer': 'LUGA',
    'ixp': 'VIEN'
}

tier1_topo = {
    'ixp_central': 'ZURI',
    'ixp_out': 'BASE',
    'peer1': 'ZURI',
    'peer2': 'ZURI',
    'provider1': 'ZURI',
    'provider2': 'ZURI' 
}

stub_topo = {
    'ixp': 'BASE',
    'peer': 'ZURI',
    'customer1': 'ZURI',
    'customer2': 'ZURI' 
}

all_tier1 = list(map(lambda x:str(x), sum(tier1, [])))

THROUGHPUT=100000
DELAY=1000
FD = open('aslevel_links.txt', 'w')
FD_STUDENTS = open('aslevel_links_students.txt', 'w')
LINE_NB = 0

# Utility functions used to derive which IP subnet to use for a given connection.
def update_subnet_ebgp():
    global LINE_NB
    LINE_NB += 1

def get_subnet_ebgp(n=0):
    global LINE_NB

    mod = LINE_NB%100
    div = int(LINE_NB/100)

    return '179.'+str(div)+'.'+str(mod)+'.'+str(n)+'/24'

# This is the main function used to print every external connection within the mini-Internet.
def print_connection(grp1, r1, type1, grp2, r2, type2, ixp=None):
    global FD
    global FD_STUDENTS
    global THROUGHPUT
    global DELAY

    ixp_addr1 = '180.{}.0.{}/24'.format(grp2, grp1)
    ixp_addr2 = '180.{}.0.{}/24'.format(grp2, grp2)

    if ixp is None: update_subnet_ebgp()
    FD.write('{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\n'.format( \
        str(grp1), \
        r1, \
        type1, \
        str(grp2), \
        r2, \
        type2,
        THROUGHPUT, \
        DELAY, \
        get_subnet_ebgp() if ixp is None else ixp))

    FD_STUDENTS.write('{}\t{}\t{}\t{}\t{}\t{}\t{}\n'.format( \
        str(grp1), \
        r1, \
        type1, \
        str(grp2), \
        r2, \
        type2,
        get_subnet_ebgp(1) if ixp is None else ixp_addr1))

    FD_STUDENTS.write('{}\t{}\t{}\t{}\t{}\t{}\t{}\n'.format( \
        str(grp2), \
        r2, \
        type2, \
        str(grp1), \
        r1, \
        type1,
        get_subnet_ebgp(2) if ixp is None else ixp_addr2))


# First focuses on the connections that pertain to Tier1 ASes
block_nb = 0
for b in tier1:
    left = b[0]
    right = b[1]

    # Commections specific to the Tier1 AS on the left of the block
    peer_other_block = tier1[(block_nb+1)%len(transit)][1]
    print_connection(left, tier1_topo['peer2'], 'Peer', peer_other_block, tier1_topo['peer2'], 'Peer')

    customer1 = transit[block_nb][2]
    customer2 = transit[block_nb][3]

    print_connection(left, tier1_topo['provider1'], 'Provider', customer1, transit_as_topo['customer2'], 'Customer')
    print_connection(left, tier1_topo['provider2'], 'Provider', customer2, transit_as_topo['customer1'], 'Customer')

    ixp1 = ixp_central
    print_connection(left, tier1_topo['ixp_central'], 'Peer', ixp1, None, 'Peer', ixp=','.join(all_tier1))

    ixp2 = ixp_out[block_nb]
    print_connection(left, tier1_topo['ixp_out'], 'Peer', ixp2, None, 'Peer', \
        ixp=','.join(map(lambda x:str(x), transit[(block_nb+1)%len(tier1)])))


    # Connections shared between the left and right ASes
    print_connection(left, tier1_topo['peer1'], 'Peer', right, tier1_topo['peer1'], 'Peer')


    # Commections specific to the Tier1 AS on the right of the block
    peer_other_block = tier1[(block_nb-1)%len(transit)][0]

    customer1 = transit[block_nb][3]
    customer2 = transit[block_nb][2]

    print_connection(right, tier1_topo['provider1'], 'Provider', customer1, transit_as_topo['customer2'], 'Customer')
    print_connection(right, tier1_topo['provider2'], 'Provider', customer2, transit_as_topo['customer1'], 'Customer')

    ixp1 = ixp_central
    print_connection(right, tier1_topo['ixp_central'], 'Peer', ixp1, None, 'Peer', ixp=','.join(all_tier1))

    ixp2 = ixp_out[block_nb-1]
    print_connection(right, tier1_topo['ixp_out'], 'Peer', ixp2, None, 'Peer', \
        ixp=','.join(map(lambda x:str(x), transit[(block_nb-1)%len(tier1)])))

    block_nb += 1

# Then focuses on the connections that pertain to Transit ASes.
block_nb = 0
for b in transit:
    i = 2

    # Commections specific to the Transit AS that only have connections with other transit ASes.
    for a in b[2:-4]:
        # Left AS.
        if i%2 == 0:
            customer1 = b[i+2]
            customer2 = b[i+3]
        # Right AS.
        else:
            customer1 = b[i+2]
            customer2 = b[i+1]

        print_connection(a, transit_as_topo['provider1'], 'Provider', customer1, transit_as_topo['customer2'], 'Customer')
        print_connection(a, transit_as_topo['provider2'], 'Provider', customer2, transit_as_topo['customer1'], 'Customer')

        # Left AS.
        if i%2 == 0:
            peer1 = b[i+1]
            peer2 = ixp_out[block_nb]

            print_connection(a, transit_as_topo['peer'], 'Peer', peer1, transit_as_topo['peer'], 'Peer')
            print_connection(a, transit_as_topo['ixp'], 'Peer', peer2, None, 'Peer', \
                ixp=','.join(map(lambda x:str(x), transit[(block_nb+1)%len(tier1)])))

        # Right AS.
        else:
            peer1 = b[i-1]
            peer2 = ixp_out[block_nb-1]

            print_connection(a, transit_as_topo['ixp'], 'Peer', peer2, None, 'Peer', \
                ixp=','.join(map(lambda x:str(x), transit[(block_nb-1)%len(tier1)])))

        i += 1

    # Commections specific to the Transit AS that have connections with Stub ASes.
    for a in b[-4:-2]:
        # Left AS.
        if i%2 == 0:
            customer1 = b[i+2]
            customer2 = b[i+3]
        # Right AS.
        else:
            customer1 = b[i+2]
            customer2 = b[i+1]

        print_connection(a, transit_as_topo['provider1'], 'Provider', customer1, stub_topo['customer2'], 'Customer')
        print_connection(a, transit_as_topo['provider2'], 'Provider', customer2, stub_topo['customer1'], 'Customer')

        # Left AS.
        if i%2 == 0:
            peer1 = b[i+1]
            peer2 = ixp_out[block_nb]

            print_connection(a, transit_as_topo['peer'], 'Peer', peer1, transit_as_topo['peer'], 'Peer')
            print_connection(a, transit_as_topo['ixp'], 'Peer', peer2, None, 'Peer', 
                ixp=','.join(map(lambda x:str(x), transit[(block_nb+1)%len(tier1)])))

        # Right AS.
        else:
            peer1 = b[i-1]
            peer2 = ixp_out[block_nb-1]

            print_connection(a, transit_as_topo['ixp'], 'Peer', peer2, None, 'Peer', \
                ixp=','.join(map(lambda x:str(x), transit[(block_nb-1)%len(tier1)])))

        i += 1

    block_nb += 1


# Configure the Stub AS
block_nb = 0
for b in transit:
    # Left AS
    left = b[-2]
    peer1 = b[-1]
    peer2 = ixp_out[block_nb]

    print_connection(left, stub_topo['peer'], 'Peer', peer1, stub_topo['peer'], 'Peer')
    print_connection(left, stub_topo['ixp'], 'Peer', peer2, None, 'Peer', \
        ixp=','.join(map(lambda x:str(x), transit[(block_nb+1)%len(tier1)])))

    # Right AS
    right = b[-1]
    peer1 = b[-2]
    peer2 = ixp_out[block_nb-1]
    print_connection(right, stub_topo['ixp'], 'Peer', peer2, None, 'Peer', \
        ixp=','.join(map(lambda x:str(x), transit[(block_nb-1)%len(tier1)])))

    block_nb += 1


# Compute and store all the Tier1 ASes, Transit and Stub ASes in lists
all_transit = sum(list(map(lambda x:x[2:-2], transit)), [])
all_stub = sum(list(map(lambda x:x[-2:], transit)), [])
all_ixp = ixp_out
all_ixp.append(ixp_central)

# Write the AS_config.txt file, with AS1 hosting krill.
with open('AS_config.txt', 'w') as fd:
    for asn in all_tier1+all_stub:
        # By default we set krill in AS1
        if asn == '1':
            fd.write(str(asn)+'\tAS\tConfig\tl3_routers_krill.txt\tl3_links_krill.txt\tempty.txt\tempty.txt\tempty.txt\n')
        else:
            fd.write(str(asn)+'\tAS\tConfig\tl3_routers_tier1_and_stub.txt\tl3_links_tier1_and_stub.txt\tempty.txt\tempty.txt\tempty.txt\n')

    for asn in all_transit:
        fd.write(str(asn)+'\tAS\tConfig\tl3_routers.txt\tl3_links.txt\tl2_switches.txt\tl2_hosts.txt\tl2_links.txt\n')

    for asn in all_ixp:
        fd.write(str(asn)+'\tIXP\tConfig\tN/A\tN/A\tN/A\tN/A\tN/A\n')


# cat external_links_config_students.txt | sort -k 1,1 -k 4,4 -n | cut -f 1,2,3,4,7 | sed  -e 's/Customer/customer2provider/g' | sed  -e 's/Provider/provider2customer/g' | sed  -e 's/Peer/peer2peer/g' > tmp.txt
