from netaddr import *
import random
import string

# 60 ASes
# tier1 = [[1,2],[11,12],[21,22],[31,32],[41,42],[51,52]]
# transit = [[1,2,3,4,5,6,7,8,9,10],[11,12,13,14,15,16,17,18,19,20],[21,22,23,24,25,26,27,28,29,30], \
# [31,32,33,34,35,36,37,38,39,40],[41,42,43,44,45,46,47,48,49,50],[51,52,53,54,55,56,57,58,59,60]]
# ixp_central = 80
# ixp_out = [81,82,83,84,85,86]

# 78 ASes
tier1 = [[1,2],[21,22],[41,42],[61,62],[81,82],[101,102]]
transit = [[1,2,3,4,5,6,7,8,9,10,11,12,13,14],[21,22,23,24,25,26,27,28,29,30,31,32,33,34], \
[41,42,43,44,45,46,47,48,49,50,51,52,53,54], [61,62,63,64,65,66,67,68,69,70,71,72], \
[81,82,83,84,85,86,87,88,89,90,91,92],[101,102,103,104,105,106,107,108,109,110,111,112]]
ixp_central = 120
ixp_out = [121,122,123,124,125,126]

# # 30 ASes
# tier1 = [[1,2],[11,12],[21,22]]
# transit = [[1,2,3,4,5,6,7,8,9,10],[11,12,13,14,15,16,17,18,19,20],[21,22,23,24,25,26,27,28,29,30]]
# ixp_central = 80
# ixp_out = [81,82,83]
#
# 12 ASes
# tier1 = [[1,2],[11,12]]
# transit = [[1,2,3,4],[11,12,13,14]]
# ixp_central = 80
# ixp_out = [81,82]

# 20 ASes
# tier1 = [[1,2],[11,12]]
# transit = [[1,2,3,4,5,6,7,8,9,10],[11,12,13,14,15,16,17,18,19,20]]
# ixp_central = 80
# ixp_out = [81,82]

# 40 ASes
# tier1 = [[1,2],[11,12],[21,22],[31,32]]
# transit = [[1,2,3,4,5,6,7,8,9,10],[11,12,13,14,15,16,17,18,19,20],[21,22,23,24,25,26,27,28,29,30], [31,32,33,34,35,36,37,38,39,40]]
# ixp_central = 80
# ixp_out = [81,82,83,84]

# tier1 = [[1,2],[11,12],[21,22],[31,32]]
# transit = [[1,2,3,4,5,6,7,8,9,10],[11,12,13,14,15,16,17,18,19,20],[21,22,23,24,25,26,27,28,29,30], \
# [31,32,33,34,35,36,37,38,39,40]]
# ixp_central = 80
# ixp_out = [81,82,83,84]


throughput=100000
delay=1000

# tier1 = [[1,2],[11,12]]
# transit = [[1,2,3,4],[11,12,13,14]]
# ixp_central = 80
# ixp_out = [81,82]

line_nb = 0
def update_subnet_ebgp():
    global line_nb
    line_nb += 1

def get_subnet_ebgp(n=0):
    global line_nb

    mod = line_nb%100
    div = int(line_nb/100)

    return '179.'+str(div)+'.'+str(mod)+'.'+str(n)+'/24'

#
# line_nb2 = 1
# def subnet_ebgp2():
#     global line_nb2
#
#     mod = line_nb2%100
#     div = int(line_nb2/100)
#     line_nb2 += 1
#
#     return '179.'+str(div)+'.'+str(mod)+'.0/24'

fd = open('external_links_config.txt', 'w')
fd_students = open('external_links_config_students.txt', 'w')

all_tier1 = []
for l in tier1:
    for asn in l:
        all_tier1.append(str(asn))


block_nb = 0
for b in tier1:
    # print block_nb
    left = b[0]
    right = b[1]

    # Tier 1 on the left of the block
    update_subnet_ebgp()
    fd.write(str(left)+'\t'+'ZURI\tPeer\t'+str(right)+'\t'+'ZURI\tPeer\t'+str(throughput)+'\t'+str(delay)+'\t'+str(get_subnet_ebgp())+'\n')
    peer_other_block = tier1[(block_nb+1)%len(transit)][1]
    update_subnet_ebgp()
    fd.write(str(left)+'\tZURI\tPeer\t'+str(peer_other_block)+'\tZURI\tPeer\t'+str(throughput)+'\t'+str(delay)+'\t'+str(get_subnet_ebgp())+'\n')

    customer1 = transit[block_nb][2]
    customer2 = transit[block_nb][3]

    update_subnet_ebgp()
    fd.write(str(left)+'\tZURI\tProvider\t'+str(customer1)+'\tBOST\tCustomer\t'+str(throughput)+'\t'+str(delay)+'\t'+str(get_subnet_ebgp())+'\n')
    fd_students.write(str(left)+'\tZURI\tProvider\t'+str(customer1)+'\tBOST\tCustomer\t'+str(get_subnet_ebgp(1))+'\n')
    fd_students.write(str(customer1)+'\tBOST\tCustomer\t'+str(left)+'\tZURI\tProvider\t'+str(get_subnet_ebgp(2))+'\n')
    update_subnet_ebgp()
    fd.write(str(left)+'\tZURI\tProvider\t'+str(customer1)+'\tLOND\tCustomer\t'+str(throughput)+'\t'+str(delay)+'\t'+str(get_subnet_ebgp())+'\n')
    fd_students.write(str(left)+'\tZURI\tProvider\t'+str(customer1)+'\tLOND\tCustomer\t'+str(get_subnet_ebgp(1))+'\n')
    fd_students.write(str(customer1)+'\tLOND\tCustomer\t'+str(left)+'\tZURI\tProvider\t'+str(get_subnet_ebgp(2))+'\n')

    update_subnet_ebgp()
    fd.write(str(left)+'\tZURI\tProvider\t'+str(customer2)+'\tZURI\tCustomer\t'+str(throughput)+'\t'+str(delay)+'\t'+str(get_subnet_ebgp())+'\n')
    fd_students.write(str(left)+'\tZURI\tProvider\t'+str(customer2)+'\tZURI\tCustomer\t'+str(get_subnet_ebgp(1))+'\n')
    fd_students.write(str(customer2)+'\tZURI\tCustomer\t'+str(left)+'\tZURI\tProvider\t'+str(get_subnet_ebgp(2))+'\n')

    ixp1 = ixp_central
    fd.write(str(left)+'\tLOND\tPeer\t'+str(ixp1)+'\tN/A\tPeer\t'+str(throughput)+'\t'+str(delay)+'\t'+','.join(all_tier1)+'\n')

    ixp2 = ixp_out[block_nb]
    fd.write(str(left)+'\tZURI\tPeer\t'+str(ixp2)+'\tN/A\tPeer\t'+str(throughput)+'\t'+str(delay)+'\t'+','.join(map(lambda x:str(x), transit[(block_nb+1)%len(tier1)]))+'\n')

    # Tier 1 on the right of the block
    peer_other_block = tier1[(block_nb-1)%len(transit)][0]

    customer1 = transit[block_nb][3]
    customer2 = transit[block_nb][2]

    update_subnet_ebgp()
    fd.write(str(right)+'\tZURI\tProvider\t'+str(customer1)+'\tBOST\tCustomer\t'+str(throughput)+'\t'+str(delay)+'\t'+str(get_subnet_ebgp())+'\n')
    fd_students.write(str(right)+'\tZURI\tProvider\t'+str(customer1)+'\tBOST\tCustomer\t'+str(get_subnet_ebgp(1))+'\n')
    fd_students.write(str(customer1)+'\tBOST\tCustomer\t'+str(right)+'\tZURI\tProvider\t'+str(get_subnet_ebgp(2))+'\n')
    update_subnet_ebgp()
    fd.write(str(right)+'\tZURI\tProvider\t'+str(customer1)+'\tLOND\tCustomer\t'+str(throughput)+'\t'+str(delay)+'\t'+str(get_subnet_ebgp())+'\n')
    fd_students.write(str(right)+'\tZURI\tProvider\t'+str(customer1)+'\tLOND\tCustomer\t'+str(get_subnet_ebgp(1))+'\n')
    fd_students.write(str(customer1)+'\tLOND\tCustomer\t'+str(right)+'\tZURI\tProvider\t'+str(get_subnet_ebgp(2))+'\n')

    update_subnet_ebgp()
    fd.write(str(right)+'\tZURI\tProvider\t'+str(customer2)+'\tZURI\tCustomer\t'+str(throughput)+'\t'+str(delay)+'\t'+str(get_subnet_ebgp())+'\n')
    fd_students.write(str(right)+'\tZURI\tProvider\t'+str(customer2)+'\tZURI\tCustomer\t'+str(get_subnet_ebgp(1))+'\n')
    fd_students.write(str(customer2)+'\tZURI\tCustomer\t'+str(right)+'\tZURI\tProvider\t'+str(get_subnet_ebgp(2))+'\n')

    ixp1 = ixp_central
    fd.write(str(right)+'\tLOND\tPeer\t'+str(ixp1)+'\tN/A\tPeer\t'+str(throughput)+'\t'+str(delay)+'\t'+','.join(all_tier1)+'\n')

    ixp2 = ixp_out[block_nb-1]
    fd.write(str(right)+'\tZURI\tPeer\t'+str(ixp2)+'\tN/A\tPeer\t'+str(throughput)+'\t'+str(delay)+'\t'+','.join(map(lambda x:str(x), transit[(block_nb-1)%len(tier1)]))+'\n')

    block_nb += 1

block_nb = 0
for b in transit:
    i = 2
    for a in b[2:-4]:
        if i%2 == 0:
            customer1 = b[i+2]
            customer2 = b[i+3]
        else:
            customer1 = b[i+2]
            customer2 = b[i+1]

        update_subnet_ebgp()
        fd.write(str(a)+'\tMIAM\tProvider\t'+str(customer1)+'\tBOST\tCustomer\t'+str(throughput)+'\t'+str(delay)+'\t'+str(get_subnet_ebgp())+'\n')
        fd_students.write(str(a)+'\tMIAM\tProvider\t'+str(customer1)+'\tBOST\tCustomer\t'+str(get_subnet_ebgp(1))+'\n')
        fd_students.write(str(customer1)+'\tBOST\tCustomer\t'+str(a)+'\tMIAM\tProvider\t'+str(get_subnet_ebgp(2))+'\n')
        update_subnet_ebgp()
        fd.write(str(a)+'\tGENE\tProvider\t'+str(customer1)+'\tLOND\tCustomer\t'+str(throughput)+'\t'+str(delay)+'\t'+str(get_subnet_ebgp())+'\n')
        fd_students.write(str(a)+'\tGENE\tProvider\t'+str(customer1)+'\tLOND\tCustomer\t'+str(get_subnet_ebgp(1))+'\n')
        fd_students.write(str(customer1)+'\tLOND\tCustomer\t'+str(a)+'\tGENE\tProvider\t'+str(get_subnet_ebgp(2))+'\n')
        update_subnet_ebgp()
        fd.write(str(a)+'\tATLA\tProvider\t'+str(customer2)+'\tZURI\tCustomer\t'+str(throughput)+'\t'+str(delay)+'\t'+str(get_subnet_ebgp())+'\n')
        fd_students.write(str(a)+'\tATLA\tProvider\t'+str(customer2)+'\tZURI\tCustomer\t'+str(get_subnet_ebgp(1))+'\n')
        fd_students.write(str(customer2)+'\tZURI\tCustomer\t'+str(a)+'\tATLA\tProvider\t'+str(get_subnet_ebgp(2))+'\n')

        if i%2 == 0:
            peer1 = b[i+1]
            peer2 = ixp_out[block_nb]

            update_subnet_ebgp()
            fd.write(str(a)+'\tPARI\tPeer\t'+str(peer1)+'\tPARI\tPeer\t'+str(throughput)+'\t'+str(delay)+'\t'+str(get_subnet_ebgp())+'\n')
            fd_students.write(str(a)+'\tPARI\tPeer\t'+str(peer1)+'\tPARI\tPeer\t'+str(get_subnet_ebgp(1))+'\n')
            fd_students.write(str(peer1)+'\tPARI\tPeer\t'+str(a)+'\tPARI\tPeer\t'+str(get_subnet_ebgp(2))+'\n')

            fd.write(str(a)+'\tNEWY\tPeer\t'+str(peer2)+'\tN/A\tPeer\t'+str(throughput)+'\t'+str(delay)+'\t'+','.join(map(lambda x:str(x), transit[(block_nb+1)%len(tier1)]))+'\n')
            fd_students.write(str(a)+'\tNEWY\tPeer\t'+str(peer2)+'\tIXP'+str(peer2)+'\tPeer\t'+'180.'+str(peer2)+'.0.'+str(a)+'/24\n')

        else:
            peer1 = b[i-1]
            peer2 = ixp_out[block_nb-1]

            fd.write(str(a)+'\tNEWY\tPeer\t'+str(peer2)+'\tN/A\tPeer\t'+str(throughput)+'\t'+str(delay)+'\t'+','.join(map(lambda x:str(x), transit[(block_nb-1)%len(tier1)]))+'\n')
            fd_students.write(str(a)+'\tNEWY\tPeer\t'+str(peer2)+'\tIXP'+str(peer2)+'\tPeer\t'+'180.'+str(peer2)+'.0.'+str(a)+'/24\n')

        i += 1

    for a in b[-4:-2]:
        if i%2 == 0:
            customer1 = b[i+2]
            customer2 = b[i+3]
        else:
            customer1 = b[i+2]
            customer2 = b[i+1]

        update_subnet_ebgp()
        fd.write(str(a)+'\tMIAM\tProvider\t'+str(customer1)+'\tZURI\tCustomer\t'+str(throughput)+'\t'+str(delay)+'\t'+str(get_subnet_ebgp())+'\n')
        fd_students.write(str(a)+'\tMIAM\tProvider\t'+str(customer1)+'\tZURI\tCustomer\t'+str(get_subnet_ebgp(1))+'\n')
        fd_students.write(str(customer1)+'\tZURI\tCustomer\t'+str(a)+'\tMIAM\tProvider\t'+str(get_subnet_ebgp(2))+'\n')
        update_subnet_ebgp()
        fd.write(str(a)+'\tGENE\tProvider\t'+str(customer1)+'\tZURI\tCustomer\t'+str(throughput)+'\t'+str(delay)+'\t'+str(get_subnet_ebgp())+'\n')
        fd_students.write(str(a)+'\tGENE\tProvider\t'+str(customer1)+'\tZURI\tCustomer\t'+str(get_subnet_ebgp(1))+'\n')
        fd_students.write(str(customer1)+'\tZURI\tCustomer\t'+str(a)+'\tGENE\tProvider\t'+str(get_subnet_ebgp(2))+'\n')
        update_subnet_ebgp()
        fd.write(str(a)+'\tATLA\tProvider\t'+str(customer2)+'\tZURI\tCustomer\t'+str(throughput)+'\t'+str(delay)+'\t'+str(get_subnet_ebgp())+'\n')
        fd_students.write(str(a)+'\tATLA\tProvider\t'+str(customer2)+'\tZURI\tCustomer\t'+str(get_subnet_ebgp(1))+'\n')
        fd_students.write(str(customer2)+'\tZURI\tCustomer\t'+str(a)+'\tATLA\tProvider\t'+str(get_subnet_ebgp(2))+'\n')

        if i%2 == 0:
            peer1 = b[i+1]
            peer2 = ixp_out[block_nb]

            update_subnet_ebgp()
            fd.write(str(a)+'\tPARI\tPeer\t'+str(peer1)+'\tPARI\tPeer\t'+str(throughput)+'\t'+str(delay)+'\t'+str(get_subnet_ebgp())+'\n')
            fd_students.write(str(a)+'\tPARI\tPeer\t'+str(peer1)+'\tPARI\tPeer\t'+str(get_subnet_ebgp(1))+'\n')
            fd_students.write(str(peer1)+'\tPARI\tPeer\t'+str(a)+'\tPARI\tPeer\t'+str(get_subnet_ebgp(2))+'\n')

            fd.write(str(a)+'\tNEWY\tPeer\t'+str(peer2)+'\tN/A\tPeer\t'+str(throughput)+'\t'+str(delay)+'\t'+','.join(map(lambda x:str(x), transit[(block_nb+1)%len(tier1)]))+'\n')
            fd_students.write(str(a)+'\tNEWY\tPeer\t'+str(peer2)+'\tIXP'+str(peer2)+'\tPeer\t'+'180.'+str(peer2)+'.0.'+str(a)+'/24\n')

        else:
            peer1 = b[i-1]
            peer2 = ixp_out[block_nb-1]

            fd.write(str(a)+'\tNEWY\tPeer\t'+str(peer2)+'\tN/A\tPeer\t'+str(throughput)+'\t'+str(delay)+'\t'+','.join(map(lambda x:str(x), transit[(block_nb-1)%len(tier1)]))+'\n')
            fd_students.write(str(a)+'\tNEWY\tPeer\t'+str(peer2)+'\tIXP'+str(peer2)+'\tPeer\t'+'180.'+str(peer2)+'.0.'+str(a)+'/24\n')

        i += 1

    block_nb += 1


# Configure the Stub AS
block_nb = 0
for b in transit:
    # Left AS
    left = b[-2]
    peer1 = b[-1]
    peer2 = ixp_out[block_nb]

    update_subnet_ebgp()
    fd.write(str(left)+'\tZURI\tPeer\t'+str(peer1)+'\tZURI\tPeer\t'+str(throughput)+'\t'+str(delay)+'\t'+str(get_subnet_ebgp())+'\n')
    fd.write(str(left)+'\tZURI\tPeer\t'+str(peer2)+'\tN/A\tPeer\t'+str(throughput)+'\t'+str(delay)+'\t'+','.join(map(lambda x:str(x), transit[(block_nb+1)%len(tier1)]))+'\n')

    # Right AS
    right = b[-1]
    peer1 = b[-2]
    peer2 = ixp_out[block_nb-1]
    fd.write(str(right)+'\tZURI\tPeer\t'+str(peer2)+'\tN/A\tPeer\t'+str(throughput)+'\t'+str(delay)+'\t'+','.join(map(lambda x:str(x), transit[(block_nb-1)%len(tier1)]))+'\n')

    block_nb += 1

fd.close()

all_tier1 = []
for i in tier1:
    for j in i:
        all_tier1.append(j)

all_stub = []
for i in transit:
    for j in i[-2:]:
        all_stub.append(j)

all_transit = []
for i in transit:
    for j in i[2:-2]:
        all_transit.append(j)

all_ixp = []
all_ixp.append(ixp_central)
for i in ixp_out:
    all_ixp.append(i)

with open('AS_config.txt', 'w') as fd:
    for asn in all_tier1+all_stub:
        fd.write(str(asn)+'\tAS\tConfig\trouter_config_small.txt\tinternal_links_config_small.txt\tlayer2_switches_config_empty.txt\tlayer2_hosts_config_empty.txt\tlayer2_links_config_empty.txt\n')

    for asn in all_transit:
        fd.write(str(asn)+'\tAS\tConfig\trouter_config_full.txt\tinternal_links_config.txt\tlayer2_switches_config.txt\tlayer2_hosts_config.txt\tlayer2_links_config.txt\n')

    for asn in all_ixp:
        fd.write(str(asn)+'\tIXP\tConfig\tN/A\tN/A\tN/A\tN/A\tN/A\n')


# cat external_links_config_students.txt | sort -k 1,1 -k 4,4 -n | cut -f 1,2,3,4,7 | sed  -e 's/Customer/customer2provider/g' | sed  -e 's/Provider/provider2customer/g' | sed  -e 's/Peer/peer2peer/g' > tmp.txt
