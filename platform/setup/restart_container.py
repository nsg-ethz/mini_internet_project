from .config import *
from config.subnet_config import *
from .helper import run_cmd, clean_ctn_netns, clean_ip_link, get_docker_pid, create_netns_symlink
from .connect_external import connect_external
from .connect_internal import connect_l2, connect_l3, connect_l3_host, connect_switch
from .connect_services import connect_dns, connect_dns_measurement, connect_measurement, connect_matrix
from ipaddress import IPv4Interface,IPv6Interface
import time


def get_vlan_tags(l2_network: L2Network):
    vlan_tags: set[int] = set()
    vlan_tags = vlan_tags.union(set([host.vlan for host in l2_network.hosts.values() if isinstance(host.vlan,int)]))
    return vlan_tags


def restart_container(cnt_name: str):

    run_cmd(f"docker kill {cnt_name} 2>/dev/null")
    clean_ctn_netns(get_docker_pid(cnt_name))
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
    host_pid = get_docker_pid(host_cnt)
    host = router.hosts[index]

    restart_container(host_cnt)

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
    router_pid = get_docker_pid(router_cnt)
    domain = config.as_es[as_no]

    restart_container(router_cnt)

    if isinstance(domain,AS):
        # connect to l3 host
        for index, host in enumerate(router.hosts):
            connect_l3_host(as_no, index, router, domain.auto)

        # connect to switch
        for l2_network in domain.l2_networks.values():
            for switch in l2_network.switches:
                if switch.router == router.name:
                    connect_switch(as_no, switch, l2_network.name)
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
                    l2_routers = [switch.router for switch in l2_network.switches if switch.router != "N/A"]
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
    host_pid = get_docker_pid(host_cnt)

    restart_container(host_cnt)
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


def restart_one_l2_switch(as_no: int, switch: Switch, l2_network: L2Network, autoconfig: bool):
    switch_cnt = f"{as_no}_L2_{l2_network.name}_{switch.name}"
    
    switch_pid = get_docker_pid(switch_cnt)
    restart_container(switch_cnt)

    connect_switch(as_no, switch, l2_network.name)
    gateway_pid = get_docker_pid(f"{as_no}_{switch.router}router")

    create_netns_symlink(gateway_pid)
    for vlan in get_vlan_tags(l2_network):
        run_cmd(f"ip netns exec {gateway_pid} ip link add link {switch.router}-L2 name {switch.router}-L2.{vlan} type vlan id {vlan}")

    run_cmd(f"ip netns exec {switch_pid} ip link set dev eth0 down")
    run_cmd(f"ip netns exec {switch_pid} ip link set dev eth0 name ssh")
    run_cmd(f"ip netns exec {switch_pid} ip link set dev ssh up")

    for l2_link in l2_network.links:         
        
        connect_l2(as_no, l2_link, l2_network)
    
    for l2_host_name, l2_host in l2_network.hosts.items():
        host_link = [link.endpoints for link in l2_network.links if l2_host_name in link.endpoints][0]
        switch_name = host_link[0] if host_link[1]==l2_host_name else host_link[1]

        if switch.name == switch_name:
            
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
                
    
    print("Restarted L2 Switch")
    return


def restart_one_ixp(config: Topology, as_no: int):
    
    ixp_cnt = f"{as_no}_IXP"

    restart_container(ixp_cnt)

    # need enough time for each router to clean up the old IXP interface
    time.sleep(5)

    for link in config.external_links:
        if link.src[0] == as_no or link.dst[0] == as_no:
            connect_external(link,config.as_es)
    
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

    return
