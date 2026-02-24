from .config import *
from config.subnet_config import *
from .helper import *
from ipaddress import IPv4Interface
from multiprocessing import Pool
import docker
import os

def connect_l3_host_router_group(group_no: int, domain: Domain):
    
    if isinstance(domain, AS):

        for router_name, router in domain.routers.items():

            for i, host in enumerate(router.hosts):
                extra = f"{i}" if len(router.services) > 1 else ""
                router_cnt_name = f"{group_no}_{router_name}router"
                router_intf_name = f"host{extra}"
                host_cnt_name = f"{group_no}_{router.name}host{extra}"
                host_intf_name = f"{router.name}router"
                
                pid_router, pid_host = connect_two_interfaces(router_cnt_name,router_intf_name,host_cnt_name,host_intf_name, perf=None)
                
                run_cmd(f"ip netns exec {pid_host} ip route del default", check=False)
                run_cmd(f"ip netns exec {pid_router} ip route del default", check=False)

                if domain.auto:
                    ip_router = str(IPv4Interface(subnet_host_router(group_no, router.id, "router")).ip)
                    subnet_host=subnet_host_router(group_no, router.id, "host")

                    run_cmd(f"ip netns exec {pid_host} ip addr add {subnet_host} dev {host_intf_name}")
                    run_cmd(f"ip netns exec {pid_host} ip route add default via {ip_router}")
        print(f"Connected Host to Router in group {group_no}")



def connect_l3_host_router(config: Topology, directory: Path):

    pool = Pool(processes = get_num_threads())
    inputs = [(group_no,domain) for group_no, domain in config.as_es.items()]
    pool.starmap(connect_l3_host_router_group, inputs)



def connect_l2_network_group(group_no: int, domain: Domain):
    
    if isinstance(domain, AS):
        client = docker.from_env()

        for l2_name, l2_network in domain.l2_networks.items():

            # start switches
            for switch in l2_network.switches:
                cnt = client.containers.get(f"{group_no}_L2_{l2_name}_{switch.name}")
                cnt.exec_run("ovs-vsctl add-br br0")
                cnt.exec_run("ovs-vsctl set bridge br0 stp_enable=true")
                cnt.exec_run("ovs-vsctl set-fail-mode br0 standalone")
                cnt.exec_run(f"ovs-vsctl set bridge br0 other_config:stp-system-id={switch.mac}")
                cnt.exec_run(f"ovs-vsctl set bridge br0 other_config:stp-priority={switch.bridge_id}")
                
                thrp = os.environ["DEFAULT_THROUGHPUT"]
                delay = os.environ["DEFAULT_DELAY"] 
                buffer = os.environ["DEFAULT_BUFFER"]

                if switch.router != "N/A":
                    cnt_router = f"{group_no}_{switch.router}router"
                    intf_router = f"{switch.router}-L2"
                    cnt_switch = f"{group_no}_L2_{l2_name}_{switch.name}"
                    intf_switch = f"{switch.router}router"
                    connect_two_interfaces(cnt_router,intf_router,cnt_switch,intf_switch,(thrp,delay,buffer))

                    client.containers.get(cnt_switch).exec_run(f"ovs-vsctl add-port br0 {intf_switch}")

            
            for l2_link in l2_network.links:
                
                cnt_1 = f"{group_no}_L2_{l2_name}_{l2_link.endpoints[0]}"
                intf_1 = f"{group_no}-{l2_link.endpoints[1]}"
                cnt_2 = f"{group_no}_L2_{l2_name}_{l2_link.endpoints[1]}"
                intf_2 = f"{group_no}-{l2_link.endpoints[0]}"
                
                thrp = f"{l2_link.data.throughput_mbit}mbit"
                delay = f"{l2_link.data.delay_ms}ms"
                buffer = f"{l2_link.data.max_buffer_ms}ms"

                connect_two_interfaces(cnt_1,intf_1,cnt_2,intf_2,(thrp,delay,buffer))

                switch_names = [switch.name for switch in l2_network.switches]

                if l2_link.endpoints[0] in switch_names and l2_link.endpoints[1] in switch_names :
                    cnt_sw1 = client.containers.get(f"{group_no}_L2_{l2_name}_{l2_link.endpoints[0]}")
                    cnt_sw1.exec_run(f"ovs-vsctl add-port br0 {intf_1}")
                    cnt_sw1.exec_run(f"ovs-vsctl set Port {intf_1} trunks=0")
                    cnt_sw2 = client.containers.get(f"{group_no}_L2_{l2_name}_{l2_link.endpoints[1]}")
                    cnt_sw2.exec_run(f"ovs-vsctl add-port br0 {intf_2}")
                    cnt_sw2.exec_run(f"ovs-vsctl set Port {intf_2} trunks=0")
                    

                elif l2_link.endpoints[0] in switch_names:
                    command = f"ovs-vsctl add-port br0 {intf_1}"
                    client.containers.get(f"{group_no}_L2_{l2_name}_{l2_link.endpoints[0]}").exec_run(command)

                elif l2_link.endpoints[1] in switch_names:
                    command = f"ovs-vsctl add-port br0 {intf_2}"
                    client.containers.get(f"{group_no}_L2_{l2_name}_{l2_link.endpoints[1]}").exec_run(command)

        print(f"Connected L2 network in group {group_no}")


def connect_l2_network(config: Topology, directory: Path):

    run_cmd("modprobe 8021q")

    os.environ["DEFAULT_THROUGHPUT"] = config.environment["DEFAULT_THROUGHPUT"]
    os.environ["DEFAULT_DELAY"] = config.environment["DEFAULT_DELAY"]
    os.environ["DEFAULT_BUFFER"] = config.environment["DEFAULT_BUFFER"]

    pool = Pool(processes = get_num_threads())
    inputs = [(group_no,domain) for group_no, domain in config.as_es.items()]
    pool.starmap(connect_l2_network_group, inputs)


def connect_l3_network_group(group_no: int, domain: Domain):
    
    if isinstance(domain, AS):

        for link in domain.internal_links:
            cnt_router_1 = f"{group_no}_{link.endpoints[0]}router"
            intf_router_1 = f"port_{link.endpoints[1]}"
            cnt_router_2 = f"{group_no}_{link.endpoints[1]}router"
            intf_router_2 = f"port_{link.endpoints[0]}"
            thrp = f"{link.data.throughput_mbit}mbit"
            delay = f"{link.data.delay_ms}ms"
            buffer = f"{link.data.max_buffer_ms}ms"

            connect_two_interfaces(cnt_router_1,intf_router_1,cnt_router_2,intf_router_2, (thrp,delay,buffer))

        print(f"Connected L3 network in group {group_no}")


def connect_l3_network(config: Topology, directory: Path):
    pool = Pool(processes = get_num_threads())
    inputs = [(group_no,domain) for group_no, domain in config.as_es.items()]
    pool.starmap(connect_l3_network_group, inputs)
