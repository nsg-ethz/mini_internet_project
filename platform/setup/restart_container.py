from pathlib import Path
import sys, os

if os.geteuid() != 0:
    exit("You need to have root privileges to run this script.")

# setting path
main_folder = str(Path(__file__).parent.parent.resolve())
sys.path.append(main_folder)

from setup.config import *
from setup.subnet_config import *
from setup.helper import run_cmd, clean_ctn_netns, clean_ip_link, get_docker_pid, create_netns_symlink
from setup.connect_external import connect_external
from setup.connect_internal import connect_l2, connect_l3, connect_l3_host, connect_switch
from setup.connect_services import connect_dns, connect_dns_measurement, connect_measurement, connect_matrix
from ipaddress import IPv4Interface,IPv6Interface
import time


def get_vlan_tags(l2_network: L2Network):
    vlan_tags: set[int] = set()
    vlan_tags = vlan_tags.union(set([host.vlan for host in l2_network.hosts.values() if isinstance(host.vlan,int)]))
    return vlan_tags


def restart_container(cnt_name: str):
    pid = get_docker_pid(cnt_name)
    run_cmd(f"docker kill {cnt_name} 2>/dev/null")
    clean_ctn_netns(pid)
    clean_ip_link()
    run_cmd(f"docker restart {cnt_name} 1>/dev/null")
    return


def rename_ssh_intf(pid: int):
    run_cmd(f"ip netns exec {pid} ip link set dev eth0 down")
    run_cmd(f"ip netns exec {pid} ip link set dev eth0 name ssh")
    run_cmd(f"ip netns exec {pid} ip link set dev ssh up")
    return


def restart_one_l3_host(as_no: int, router: Router, index: int, autoconfig: bool):
    extra = f"{index}" if len(router.services) > 1 else ""
    host_cnt = f"{as_no}_{router.name}host{extra}"
    host = router.hosts[index]

    restart_container(host_cnt)

    host_pid = get_docker_pid(host_cnt)

    connect_l3_host(as_no,index,router,autoconfig)

    rename_ssh_intf(host_pid)
    

    if host.type == HostType.KRILL:
        run_cmd(f"ip netns exec {host_pid} ip link set dev eth1 down")
        run_cmd(f"ip netns exec {host_pid} ip link set dev eth1 name ssh")
        run_cmd(f"ip netns exec {host_pid} ip link set dev krill up")
    
    if host.type == HostType.ROUTINATOR:
        run_cmd(f"docker exec {host_cnt} routinator update")

    print("Restarted L3 Host")
    return


def restart_one_router(config: Topology, as_no: int, router: Router):
    router_cnt = f"{as_no}_{router.name}router"
    domain = config.as_es[as_no]

    restart_container(router_cnt)

    router_pid = get_docker_pid(router_cnt)

    if isinstance(domain,AS):
        # connect to l3 host
        for index, _ in enumerate(router.hosts):
            connect_l3_host(as_no, index, router, domain.auto)

        # connect to switch
        for l2_network in domain.l2_networks.values():
            for switch in l2_network.switches.values():
                if switch.router == router.name:
                    connect_switch(as_no, switch, l2_network.name, config.environment)
                    for vlan in get_vlan_tags(l2_network):
                        run_cmd(f"ip netns exec {router_pid} ip link add link {switch.router}-L2 name {switch.router}-L2.{vlan} type vlan id {vlan}")

        for tunnel in domain.l2_tunnel:
            if tunnel[0] in domain.routers and tunnel[1] in domain.routers:
                router_1 = domain.routers[tunnel[0]]
                router_2 = domain.routers[tunnel[1]]
                cnt_1 = f"{as_no}_{router_1.name}router"
                cnt_2 = f"{as_no}_{router_2.name}router"
                ip_local_router = str(IPv4Interface(subnet_router(as_no, router_1.id)).ip)
                ip_remote_router = str(IPv4Interface(subnet_router(as_no, router_2.id)).ip)

                run_cmd(f"docker exec -d {cnt_1} \"ip tunnel add tun6to4 mode sit remote {ip_remote_router} local {ip_local_router} ttl 255\" ")
                run_cmd(f"docker exec -d {cnt_2} \"ip tunnel add tun6to4 mode sit remote {ip_local_router} local {ip_remote_router} ttl 255\" ")
                run_cmd(f"docker exec -d {cnt_1} \"ip link set tun6to4 up\" ")
                run_cmd(f"docker exec -d {cnt_2} \"ip link set tun6to4 up\" ")

                tunnel_location: list[int] = [0, 0]

                for i, l2_network in enumerate(domain.l2_networks.values()):
                    l2_routers = [switch.router for switch in l2_network.switches.values() if switch.router != "N/A"]
                    if router_1.name in l2_routers:
                        tunnel_location[0] = i
                    if router_2.name in l2_routers:
                        tunnel_location[1] = i

                for i, l2_network in enumerate(domain.l2_networks.values()):
                    for vlan in get_vlan_tags(l2_network):
                        if tunnel_location[0] != i:
                            subnet_1 = subnet_l2_ipv6(as_no, i, vlan, 0)
                            run_cmd(f"docker exec -d {cnt_1} \"ip route add {subnet_1} dev tun6to4\" ")

                        if tunnel_location[1] != i:
                            subnet_2 = subnet_l2_ipv6(as_no, i, vlan, 0)
                            run_cmd(f"docker exec -d {cnt_1} \"ip route add {subnet_2} dev tun6to4\" ") 

        # add internal links
        for link in domain.internal_links:
            if router.name == link.endpoints[0] or router.name == link.endpoints[1]:
                connect_l3(as_no, link)

        
        for link in config.external_links:
            if (link.src[0] == as_no and link.src[1] == router.name) or (link.dst[0] == as_no and link.dst[1] == router.name):
                connect_external(link, config.as_es)

        if Service.MEASUREMENT in router.services:
            connect_measurement(as_no, router.name)

        if Service.MATRIX in router.services:
            connect_matrix(as_no, router.name)

        if Service.DNS in router.services:
            connect_dns(as_no, router.name)

        rename_ssh_intf(router_pid)

        
        time.sleep(5)

        run_cmd(f"docker exec {router_cnt} vtysh -c 'clear ip bgp *' -c 'exit'")
        run_cmd(f"docker exec {router_cnt} vtysh -c 'conf t' -c 'rpki' -c 'rpki reset' -c 'exit' -c 'exit'")

    print("Restarted Router")
    return

def restart_one_l2_host(as_no: int, l2_host_name: str, l2_network: L2Network, autoconfig: bool):
    host_cnt = f"{as_no}_L2_{l2_network.name}_{l2_host_name}"

    restart_container(host_cnt)

    host_pid = get_docker_pid(host_cnt)

    for l2_link in l2_network.links:
        if l2_host_name == l2_link.endpoints[0] or l2_host_name == l2_link.endpoints[1]:
            host_link = [link.endpoints for link in l2_network.links if l2_host_name in link.endpoints][0]
            switch_name = host_link[0] if host_link[1]==l2_host_name else host_link[1]

            connect_l2(as_no, l2_link, l2_network)

    rename_ssh_intf(host_pid)
    l2_host = l2_network.hosts[l2_host_name]

    if autoconfig:
        subnet_l2_host = subnet_l2(as_no, l2_network.id, l2_host.vlan, l2_host.l2_id+2)
        subnet_l2_host_ipv6 = subnet_l2_ipv6(as_no, l2_network.id, l2_host.vlan, l2_host.l2_id+2)

        pid = get_docker_pid(f"{as_no}_L2_{l2_network.name}_{l2_host_name}")

        run_cmd(f"ip netns exec {pid} ip a add {subnet_l2_host} dev {as_no}-{switch_name}")
        run_cmd(f"ip netns exec {pid} ip -6 a add {subnet_l2_host_ipv6} dev {as_no}-{switch_name}")
            
        subnet_gw = str(IPv4Interface(subnet_l2(as_no, l2_network.id, l2_host.vlan, 1)).ip)
        subnet_gw_ipv6 = str(IPv6Interface(subnet_l2_ipv6(as_no, l2_network.id, l2_host.vlan, 1)).ip)
        run_cmd(f"ip netns exec {pid} ip route add default via {subnet_gw}")
        run_cmd(f"ip netns exec {pid} ip -6 route add default via {subnet_gw_ipv6}")

    print("Restarted L2 host")
    return


def restart_one_l2_switch(as_no: int, switch: Switch, l2_network: L2Network, autoconfig: bool, env: dict[str, str]):
    switch_cnt = f"{as_no}_L2_{l2_network.name}_{switch.name}"

    restart_container(switch_cnt)

    switch_pid = get_docker_pid(switch_cnt)

    connect_switch(as_no, switch, l2_network.name, env)
    gateway_pid = get_docker_pid(f"{as_no}_{switch.router}router")

    create_netns_symlink(gateway_pid)
    for vlan in get_vlan_tags(l2_network):
        run_cmd(f"ip netns exec {gateway_pid} ip link add link {switch.router}-L2 name {switch.router}-L2.{vlan} type vlan id {vlan}")

    rename_ssh_intf(switch_pid)

    for l2_link in l2_network.links:         
        if switch.name == l2_link.endpoints[0] or switch.name==l2_link.endpoints[1]:
            connect_l2(as_no, l2_link, l2_network)
    
    for l2_host_name, l2_host in l2_network.hosts.items():
        host_link = [link.endpoints for link in l2_network.links if l2_host_name in link.endpoints][0]
        sw_name = host_link[0] if host_link[1]==l2_host_name else host_link[1]

        if switch.name == sw_name:
            
            if autoconfig:
                subnet_l2_host = subnet_l2(as_no, l2_network.id, l2_host.vlan, l2_host.l2_id+2)
                subnet_l2_host_ipv6 = subnet_l2_ipv6(as_no, l2_network.id, l2_host.vlan, l2_host.l2_id+2)

                pid = get_docker_pid(f"{as_no}_L2_{l2_network.name}_{l2_host_name}")

                run_cmd(f"ip netns exec {pid} ip a add {subnet_l2_host} dev {as_no}-{sw_name}")
                run_cmd(f"ip netns exec {pid} ip -6 a add {subnet_l2_host_ipv6} dev {as_no}-{sw_name}")
                    
                subnet_gw = str(IPv4Interface(subnet_l2(as_no, l2_network.id, l2_host.vlan, 1)).ip)
                subnet_gw_ipv6 = str(IPv6Interface(subnet_l2_ipv6(as_no, l2_network.id, l2_host.vlan, 1)).ip)
                run_cmd(f"ip netns exec {pid} ip route add default via {subnet_gw}")
                run_cmd(f"ip netns exec {pid} ip -6 route add default via {subnet_gw_ipv6}")
                
    
    print("Restarted L2 Switch")
    return


def restart_one_ixp(config: Topology, as_no: int):
    
    ixp_cnt = f"{as_no}_IXP"

    restart_container(ixp_cnt)
    
    time.sleep(5)

    for link in config.external_links:
        if link.src[0] == as_no or link.dst[0] == as_no:
            connect_external(link, config.as_es)
            time.sleep(1)
    
    subnet_ixp = subnet_router_IXP(-1, as_no, "IXP")
    # manually load the config as it won't be auto-loaded
    run_cmd(f"docker exec -d {ixp_cnt} bash -c 'vtysh -c \"conf t\" -c \"$(tail -n +2 conf_full.sh)\" -c \"exit\"' &")
    run_cmd(f"docker exec -d {ixp_cnt} bash -c \"ip addr add {subnet_ixp} dev IXP\"")
    run_cmd(f"docker exec -d {ixp_cnt} bash -c \"ip link set dev IXP up\"")

    # clear bgp
    run_cmd(f"docker exec -d {ixp_cnt} vtysh -c 'clear ip bgp *' -c 'exit'")

    print("Restarted IXP")
    return


def restart_one_ssh(as_no: int):
    restart_container(f"{as_no}_ssh")
    print("Restarted SSH container")
    return


def restart_web_proxy():

    run_cmd("docker kill WEB 2>/dev/null")
    run_cmd("docker kill PROXY 2>/dev/null")

    run_cmd("docker restart WEB 1>/dev/null")
    run_cmd("docker restart PROXY 1>/dev/null")

    print("Restarted WEB and PROXY")

    return


def restart_measurement(config: Topology):

    restart_container("MEASUREMENT")

    services: set[Service] = set()
    for domain in config.as_es.values():
        for router in domain.routers.values():
            services = services.union(router.services)

    for as_no, domain in config.as_es.items():
        if isinstance(domain, AS):
            for name, router in domain.routers.items():
                if Service.MEASUREMENT in router.services:
                    connect_measurement(as_no, name)
        
    if Service.DNS in services:
        connect_dns_measurement()

    print("Restarted Measurement")
    return


def restart_dns(config: Topology):

    restart_container("DNS")

    services: set[Service] = set()
    for domain in config.as_es.values():
        for router in domain.routers.values():
            services = services.union(router.services)

    for as_no, domain in config.as_es.items():
        if isinstance(domain, AS):
            for name, router in domain.routers.items():
                if Service.DNS in router.services:
                    connect_dns(as_no, name)

    if Service.DNS in services:
        connect_dns_measurement()

    print("Restarted DNS")
    return


def restart_matrix(config: Topology):

    restart_container("MATRIX")

    run_cmd("docker pause MATRIX")

    for as_no, domain in config.as_es.items():
        if isinstance(domain, AS):
            for name, router in domain.routers.items():
                if Service.MATRIX in router.services:
                    connect_matrix(as_no, name)

    run_cmd("docker unpause MATRIX")

    print("Restarted Matrix")
    return


if __name__ == "__main__":
    
    script_dir = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser()
    parser.add_argument('-c', '--config', default=str(script_dir.joinpath("config")))
    parser.add_argument('-v', '--verbose', action='store_true', help='Enable verbose output')
    parser.add_argument('--as_no',type=int, help="The AS number the container is in")
    parser.add_argument('--type', type=str, help="Type of container: router, l3-host, l2-host, switch, ssh, ixp, matrix, dns, measurement, web")
    parser.add_argument('--region', type=str, help="The Region of the router or l3 host or switch L2 network")
    parser.add_argument('--switch', type=str, help="The name of the switch")
    parser.add_argument('--host', type=str, help="The name of the host")
    args = parser.parse_args()
    
    topology = Topology.from_config(args)
    if args.as_no not in topology.as_es.keys():
        match args.type:
            case "matrix":
                    restart_matrix(topology)

            case "dns":
                restart_dns(topology)

            case "measurement":
                restart_measurement(topology)

            case "web":
                restart_web_proxy()
            
            case _:
                print("AS number not found")
    else:
        domain = topology.as_es[args.as_no]
        
        match args.type:

            case "router":
                if isinstance(domain, AS) and args.region in domain.routers.keys():
                    router = domain.routers[args.region]
                    restart_one_router(topology,args.as_no,router)
                else:
                    print("Router not found")

            case "l3-host":
                if isinstance(domain, AS) and args.region in domain.routers.keys():
                    router = domain.routers[args.region]
                    index = 0 if args.host == "host" else int(args.host.removeprefix("host"))
                    if index < len(router.hosts):
                        restart_one_l3_host(args.as_no, router, index, domain.auto)
                    else:
                        print("Host not found")
                else:
                    print("Router not found")

            case "l2-host":
                if isinstance(domain, AS) and args.region in domain.l2_networks.keys():
                    l2_network = domain.l2_networks[args.region]
                    if args.host in l2_network.hosts.keys():
                        restart_one_l2_host(args.as_no, args.host, l2_network, domain.auto)
                    else:
                        print("Host not found")
                else:
                    print("L2 Network not found")
            
            case "switch":
                if isinstance(domain, AS) and args.region in domain.l2_networks.keys():
                    l2_network = domain.l2_networks[args.region]
                    if args.switch in l2_network.switches.keys():
                        switch = l2_network.switches[args.switch]
                        restart_one_l2_switch(args.as_no, switch, l2_network, domain.auto, topology.environment)
                    else:
                        print("Switch not found")
                else:
                    print("L2 Network not found")

            case "ssh":
                if isinstance(domain, AS):
                    restart_one_ssh(args.as_no)
                else:
                    print("This AS does not have an ssh container")

            case "ixp":
                if isinstance(domain, IXP):
                    restart_one_ixp(topology, args.as_no)
                else:
                    print("This AS is not an IXP")

            case _:
                print("Type not found")
            
