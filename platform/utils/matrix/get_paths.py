import json
import time 
def load_config(config_dir):
    as_dic = {}
    
    with open(config_dir+'/AS_config.txt', 'r') as fd:
        for line in fd.readlines(): 
            linetab = line.rstrip('\n').split('\t')
            asn = int(linetab[0])
            astype = linetab[1]
            router_config_file = linetab[3]

            if astype == 'IXP':
                break

            as_dic[asn] = []
            fd_router = open(config_dir+'/'+router_config_file, 'r')
            for line in fd_router.readlines():
                linetab = line.replace('\t', ' ').split(' ')
                router_name = linetab[0]
                as_dic[asn].append(router_name)

    return as_dic

def get_path_as_router(group_dir, asn, router_name):
    fd = open(group_dir+'/g{}/{}/looking_glass_json.txt'.format(asn, router_name))
    print group_dir+'/g{}/{}/looking_glass_json.txt'.format(asn, router_name)

    try:
        bgp_data = json.load(fd)
    except ValueError: 
        time.sleep(1)
        bgp_data = json.load(fd)

    path_to_as = {}
    
    # BGP is not running in the router
    if 'localAS' not in bgp_data:
        return path_to_as 
    
    local_as = bgp_data['localAS']
    for prefix in bgp_data['routes']:
        for route_pref in bgp_data['routes'][prefix]:
            # print (route_pref)
            aspath = route_pref['path']
            # if aspath == '':
                # aspath = []
            # else:
                # aspath = map(lambda x:int(x), aspath.split(' '))
            # bestpath = route_pref['bestpath'] if 'bestpath' in route_pref else False

            asdest = int(prefix.split('.')[0])

            # if bestpath:
            if asdest not in path_to_as:
                path_to_as[asdest] = []
            path_to_as[asdest].append(aspath)

    return path_to_as

def get_path_as(config_dir, group_dir, asn):
    routers = load_config(config_dir)[asn]
  
    path_to_as = {}

    for r in routers:
        tmp = get_path_as_router(group_dir, asn, r)
        for asdest in tmp:
            if asdest not in path_to_as:
                path_to_as[asdest] = set()
            print (tmp[asdest])
            path_to_as[asdest] = path_to_as[asdest].union(set(tmp[asdest]))
    
    return path_to_as

if __name__ == '__main__':
    print (get_path_as('../../config', '../../groups', 3))