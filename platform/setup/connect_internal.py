from .config import *
from .subnet_config import *
from .helper import *
from ipaddress import IPv4Interface
from multiprocessing import Pool
import os


##### L3 host to router

def connect_l3_host_router(config: Topology, directory: Path):

    pool = Pool(processes = get_num_threads())
    inputs = [(group_no,domain) for group_no, domain in config.as_es.items()]
    pool.starmap(connect_l3_host_router_group, inputs)

    return


def connect_l3_host_router_group(group_no: int, domain: Domain):
    
    if isinstance(domain, AS):

        for router in domain.routers.values():

            for i, _ in enumerate(router.hosts):
                connect_l3_host(group_no, i, router, domain.auto)

        print(f"Connected Host to Router in group {group_no}")

    return


def connect_l3_host(group_no: int, index: int, router: Router, autoconfig: bool):
    extra = f"{index}" if len(router.services) > 1 else ""
    router_cnt_name = f"{group_no}_{router.name}router"
    router_intf_name = f"host{extra}"
    host_cnt_name = f"{group_no}_{router.name}host{extra}"
    host_intf_name = f"{router.name}router"

    pid_router, pid_host = connect_two_interfaces(router_cnt_name,router_intf_name,host_cnt_name,host_intf_name, perf=None)

    run_cmd(f"ip netns exec {pid_host} ip route del default", check=False)
    run_cmd(f"ip netns exec {pid_router} ip route del default", check=False)

    if autoconfig:
        ip_router = str(IPv4Interface(subnet_host_router(group_no, router.id + index, "router")).ip)
        subnet_host=subnet_host_router(group_no, router.id + index, "host")

        run_cmd(f"ip netns exec {pid_host} ip addr add {subnet_host} dev {host_intf_name}")
        run_cmd(f"ip netns exec {pid_host} ip route add default via {ip_router}")
    
    return


##### L2 network

def connect_l2_network(config: Topology, directory: Path):

    run_cmd("modprobe 8021q")

    pool = Pool(processes = get_num_threads())
    inputs = [(group_no,domain,config.environment) for group_no, domain in config.as_es.items()]
    pool.starmap(connect_l2_network_group, inputs)

    return


def connect_l2_network_group(group_no: int, domain: Domain, env: dict[str,str]):
    
    if isinstance(domain, AS):

        for l2_name, l2_network in domain.l2_networks.items():

            for switch in l2_network.switches.values():
                connect_switch(group_no, switch, l2_name, env)
            
            for l2_link in l2_network.links:         
                connect_l2(group_no, l2_link, l2_network)
        
        print(f"Connected L2 network in group {group_no}")

    return


def connect_switch(group_no: int, switch: Switch, l2_name: str, env: dict[str,str]):

    cnt = f"{group_no}_L2_{l2_name}_{switch.name}"
    run_cmd(f"docker exec -d {cnt} ovs-vsctl add-br br0")
    run_cmd(f"docker exec -d {cnt} ovs-vsctl set bridge br0 stp_enable=true")
    run_cmd(f"docker exec -d {cnt} ovs-vsctl set-fail-mode br0 standalone")
    run_cmd(f"docker exec -d {cnt} ovs-vsctl set bridge br0 other_config:stp-system-id={switch.mac}")
    run_cmd(f"docker exec -d {cnt} ovs-vsctl set bridge br0 other_config:stp-priority={switch.bridge_id}")
    
    thrp = env["DEFAULT_THROUGHPUT"]
    delay = env["DEFAULT_DELAY"] 
    buffer = env["DEFAULT_BUFFER"]

    if switch.router != "N/A":
        cnt_router = f"{group_no}_{switch.router}router"
        intf_router = f"{switch.router}-L2"
        cnt_switch = f"{group_no}_L2_{l2_name}_{switch.name}"
        intf_switch = f"{switch.router}router"
        connect_two_interfaces(cnt_router,intf_router,cnt_switch,intf_switch,(thrp,delay,buffer))

        run_cmd(f"docker exec -d {cnt_switch} ovs-vsctl add-port br0 {intf_switch}")
    

    return


def connect_l2(group_no: int, l2_link: InternalLink, l2_network: L2Network):

    cnt_1 = f"{group_no}_L2_{l2_network.name}_{l2_link.endpoints[0]}"
    intf_1 = f"{group_no}-{l2_link.endpoints[1]}"
    cnt_2 = f"{group_no}_L2_{l2_network.name}_{l2_link.endpoints[1]}"
    intf_2 = f"{group_no}-{l2_link.endpoints[0]}"
    
    thrp = f"{l2_link.data.throughput_mbit}mbit"
    delay = f"{l2_link.data.delay_ms}ms"
    buffer = f"{l2_link.data.max_buffer_ms}ms"

    connect_two_interfaces(cnt_1,intf_1,cnt_2,intf_2,(thrp,delay,buffer))

    switch_names = l2_network.switches.keys()

    if l2_link.endpoints[0] in switch_names and l2_link.endpoints[1] in switch_names :
        cnt_sw1 = f"{group_no}_L2_{l2_network.name}_{l2_link.endpoints[0]}"
        run_cmd(f"docker exec -d {cnt_sw1} ovs-vsctl add-port br0 {intf_1}")
        run_cmd(f"docker exec -d {cnt_sw1} ovs-vsctl set Port {intf_1} trunks=0")
        cnt_sw2 = f"{group_no}_L2_{l2_network.name}_{l2_link.endpoints[1]}"
        run_cmd(f"docker exec -d {cnt_sw2} ovs-vsctl add-port br0 {intf_2}")
        run_cmd(f"docker exec -d {cnt_sw2} ovs-vsctl set Port {intf_2} trunks=0")
        

    elif l2_link.endpoints[0] in switch_names:
        command = f"ovs-vsctl add-port br0 {intf_1}"
        cnt = f"{group_no}_L2_{l2_network.name}_{l2_link.endpoints[0]}"
        run_cmd(f"docker exec -d {cnt} {command}")

    elif l2_link.endpoints[1] in switch_names:
        command = f"ovs-vsctl add-port br0 {intf_2}"
        cnt = f"{group_no}_L2_{l2_network.name}_{l2_link.endpoints[1]}"
        run_cmd(f"docker exec -d {cnt} {command}")

    return


##### L3 network

def connect_l3_network(config: Topology, directory: Path):
    pool = Pool(processes = get_num_threads())
    inputs = [(group_no,domain) for group_no, domain in config.as_es.items()]
    pool.starmap(connect_l3_network_group, inputs)

    return


def connect_l3_network_group(group_no: int, domain: Domain):
    
    if isinstance(domain, AS):

        for link in domain.internal_links:
            connect_l3(group_no, link)

        print(f"Connected L3 network in group {group_no}")

    return


def connect_l3(group_no: int, link: InternalLink):
    cnt_router_1 = f"{group_no}_{link.endpoints[0]}router"
    intf_router_1 = f"port_{link.endpoints[1]}"
    cnt_router_2 = f"{group_no}_{link.endpoints[1]}router"
    intf_router_2 = f"port_{link.endpoints[0]}"
    thrp = f"{link.data.throughput_mbit}mbit"
    delay = f"{link.data.delay_ms}ms"
    buffer = f"{link.data.max_buffer_ms}ms"

    connect_two_interfaces(cnt_router_1,intf_router_1,cnt_router_2,intf_router_2, (thrp,delay,buffer))

    return
