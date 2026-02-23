from .config import *
from config.subnet_config import *
from .helper import *
from ipaddress import IPv4Interface
from multiprocessing import Pool

def connect_group(group_no: int, domain: Domain):
    
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
    pool.starmap(connect_group, inputs)

