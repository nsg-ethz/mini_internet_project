from .config import *
from config.subnet_config import *
from .helper import get_num_threads, run_cmd, get_docker_pid
from multiprocessing import Pool
from ipaddress import IPv4Interface, IPv6Interface
import docker

def layer2_config_group(group_no: int, domain: Domain, directory: Path):
    
    if isinstance(domain,AS):

        with open(f"{directory}/groups/g{group_no}/l2_setup.sh","w+") as file:
            file.write("#!/bin/bash\n\n")
            client = docker.from_env()


            for tunnel in domain.l2_tunnel:
                if tunnel[0] in domain.routers and tunnel[1] in domain.routers:
                    router_1 = domain.routers[tunnel[0]]
                    router_2 = domain.routers[tunnel[1]]
                    cnt_1 = client.containers.get(f"{group_no}_{router_1.name}router")
                    cnt_2 = client.containers.get(f"{group_no}_{router_2.name}router")
                    ip_local_router = str(IPv4Interface(subnet_router(group_no, router_1.id)).ip)
                    ip_remote_router = str(IPv4Interface(subnet_router(group_no, router_2.id)).ip)

                    file.write(f"docker exec -d {group_no}_{router_1.name}router ip tunnel add tun6to4 mode sit remote {ip_remote_router} local {ip_local_router} ttl 255\n")
                    file.write(f"docker exec -d {group_no}_{router_2.name}router ip tunnel add tun6to4 mode sit remote {ip_local_router} local {ip_remote_router} ttl 255\n")
                    file.write(f"docker exec -d {group_no}_{router_1.name}router ip link set tun6to4 up\n")
                    file.write(f"docker exec -d {group_no}_{router_2.name}router ip link set tun6to4 up\n")
                    

                    if domain.auto:
                        cnt_1.exec_run(f"ip tunnel add tun6to4 mode sit remote {ip_remote_router} local {ip_local_router} ttl 255\n")
                        cnt_2.exec_run(f"ip tunnel add tun6to4 mode sit remote {ip_local_router} local {ip_remote_router} ttl 255\n")
                        cnt_1.exec_run(f"ip link set tun6to4 up\n")
                        cnt_2.exec_run(f"ip link set tun6to4 up\n")

                    tunnel_location: list[int] = [0, 0]
                    vlan_tags: set[int] = set()

                    for i, l2_network in enumerate(domain.l2_networks.values()):
                        vlan_tags = vlan_tags.union(set([host.vlan for host in l2_network.hosts.values() if isinstance(host.vlan,int)]))
                        l2_routers = [switch.router for switch in l2_network.switches if switch.router != "N/A"]
                        if router_1.name in l2_routers:
                            tunnel_location[0] = i
                        if router_2.name in l2_routers:
                            tunnel_location[1] = i

                    for vlan in vlan_tags:
                        for i in range(len(domain.l2_networks.values())):
                            if tunnel_location[0] != i:

                                subnet_1 = subnet_l2_ipv6(group_no, i, vlan,-1)
                                file.write(f"docker exec -d {group_no}_{router_1.name}router ip route add {subnet_1} dev tun6to4\n")

                                if domain.auto:
                                    cnt_1.exec_run(f"ip route add {subnet_1} dev tun6to4")
                            if tunnel_location[1] != i:

                                subnet_2 = subnet_l2_ipv6(group_no, i, vlan,-1)
                                file.write(f"docker exec -d {group_no}_{router_2.name}router ip route add {subnet_2} dev tun6to4\n")

                                if domain.auto:
                                    cnt_2.exec_run(f"ip route add {subnet_2} dev tun6to4") 

            

            for i, l2_network in enumerate(domain.l2_networks.values()):
                vlan_tags: set[int] = set()
                vlan_tags = vlan_tags.union(set([host.vlan for host in l2_network.hosts.values() if isinstance(host.vlan,int)]))

                for vlan in vlan_tags:
                    for router_name in [switch.router for switch in l2_network.switches if switch.router != "N/A"]:
                        
                        subnet_router_l2 = subnet_l2(group_no, i, vlan, 1)
                        subnet_router_ipv6 = subnet_l2_ipv6(group_no, i, vlan, 1)
                        router_cnt = client.containers.get(f"{group_no}_{router_name}router")

                        if vlan != 0:
                            pid = get_docker_pid(f"{group_no}_{router_name}router")
                            

                            run_cmd(f"ip netns exec {pid} ip link add link {router_name}-L2 name {router_name}-L2.{vlan} type vlan id {vlan}")
                            
                            file.write(f"docker exec -d {group_no}_{router_name}router vtysh -c \'conf t\' -c \'interface {router_name}-L2.{vlan}\' -c \'ip address {subnet_router_l2}\'\n")
                            file.write(f"docker exec -d {group_no}_{router_name}router vtysh -c \'conf t\' -c \'interface {router_name}-L2.{vlan}\' -c \'ip address {subnet_router_ipv6}\'\n")
                            
                            if domain.auto:
                                router_cnt.exec_run(f"vtysh -c \'conf t\' -c \'interface {router_name}-L2.{vlan}\' -c \'ip address {subnet_router_l2}\'")
                                router_cnt.exec_run(f"vtysh -c \'conf t\' -c \'interface {router_name}-L2.{vlan}\' -c \'ip address {subnet_router_ipv6}\'")
                            
                        else:
                            
                            file.write(f"docker exec -d {group_no}_{router_name}router vtysh -c \'conf t\' -c \'interface {router_name}-L2\' -c \'ip address {subnet_router_l2}\'\n")
                            file.write(f"docker exec -d {group_no}_{router_name}router vtysh -c \'conf t\' -c \'interface {router_name}-L2\' -c \'ip address {subnet_router_ipv6}\'\n")

                            if domain.auto:
                                router_cnt.exec_run(f"vtysh -c \'conf t\' -c \'interface {router_name}-L2\' -c \'ip address {subnet_router_l2}\'")
                                router_cnt.exec_run(f"vtysh -c \'conf t\' -c \'interface {router_name}-L2\' -c \'ip address {subnet_router_ipv6}\'")

                for l2_host_name, l2_host in l2_network.hosts.items():

                    host_link = [link.endpoints for link in l2_network.links if l2_host_name in link.endpoints][0]
                    switch_name = host_link[0] if host_link[1]==l2_host_name else host_link[1]

                    switch_cnt = client.containers.get(f"{group_no}_L2_{l2_network.name}_{switch_name}")

                    if l2_host.vlan != 0:
                        
                        file.write(f"docker exec -d {group_no}_L2_{l2_network.name}_{switch_name} ovs-vsctl set port {group_no}-{l2_host_name} tag={l2_host.vlan}\n")

                        if domain.auto: 
                            switch_cnt.exec_run(f"ovs-vsctl set port {group_no}-{l2_host_name} tag={l2_host.vlan}")

                    subnet_l2_host = subnet_l2(group_no, i, l2_host.vlan, l2_host.l2_id+2)
                    subnet_l2_host_ipv6 = subnet_l2_ipv6(group_no, i, l2_host.vlan, l2_host.l2_id+2)

                    pid = get_docker_pid(f"{group_no}_L2_{l2_network.name}_{l2_host_name}")

                    file.write(f"ip netns exec {pid} ip a add {subnet_l2_host} dev {group_no}-{switch_name}\n")
                    file.write(f"ip netns exec {pid} ip -6 a add {subnet_l2_host_ipv6} dev {group_no}-{switch_name}\n")

                    if domain.auto:
                        run_cmd(f"ip netns exec {pid} ip a add {subnet_l2_host} dev {group_no}-{switch_name}")
                        run_cmd(f"ip netns exec {pid} ip -6 a add {subnet_l2_host_ipv6} dev {group_no}-{switch_name}")
                    
                    subnet_gw = str(IPv4Interface(subnet_l2(group_no, i, l2_host.vlan, 1)).ip)
                    subnet_gw_ipv6 = str(IPv6Interface(subnet_l2_ipv6(group_no, i, l2_host.vlan, 1)).ip)

                    file.write(f"ip netns exec {pid} ip route add default via {subnet_gw}\n")
                    file.write(f"ip netns exec {pid} ip -6 route add default via {subnet_gw_ipv6}\n")
                    
                    if domain.auto:
                        run_cmd(f"ip netns exec {pid} ip route add default via {subnet_gw}")
                        run_cmd(f"ip netns exec {pid} ip -6 route add default via {subnet_gw_ipv6}")
                
                vlan_str = ""
                for vlan in vlan_tags:
                    vlan_str += f"{vlan},"

                for link in l2_network.links:
                    
                    switches = [switch.name for switch in l2_network.switches]

                    if link.endpoints[0] in switches and link.endpoints[1] in switches:

                        cnt_sw_1 = client.containers.get(f"{group_no}_L2_{l2_network.name}_{link.endpoints[0]}")
                        cnt_sw_2 = client.containers.get(f"{group_no}_L2_{l2_network.name}_{link.endpoints[1]}")
                        
                        file.write(f"docker exec -d {group_no}_L2_{l2_network.name}_{link.endpoints[0]} ovs-vsctl set port {group_no}-{link.endpoints[1]} trunks={vlan_str[:-1]}\n")
                        file.write(f"docker exec -d {group_no}_L2_{l2_network.name}_{link.endpoints[1]} ovs-vsctl set port {group_no}-{link.endpoints[0]} trunks={vlan_str[:-1]}\n")

                        if domain.auto:
                            
                            cnt_sw_1.exec_run(f"ovs-vsctl set port {group_no}-{link.endpoints[1]} trunks={vlan_str[:-1]}")
                            cnt_sw_2.exec_run(f"ovs-vsctl set port {group_no}-{link.endpoints[0]} trunks={vlan_str[:-1]}")
                    
                
                for switch in l2_network.switches:
                    cnt_sw = client.containers.get(f"{group_no}_L2_{l2_network.name}_{switch.name}")

                    file.write(f"docker exec -d {group_no}_L2_{l2_network.name}_{switch.name} ovs-vsctl set port {switch.router}router trunks={vlan_str[:-1]}")

                    if domain.auto:
                        cnt_sw.exec_run(f"ovs-vsctl set port {switch.router}router trunks={vlan_str[:-1]}")                               
        run_cmd(f"chmod u+x {directory}/groups/g{group_no}/l2_setup.sh")


def layer2_config(config: Topology, directory: Path):

    pool = Pool(processes = get_num_threads())
    inputs = [(group_no,domain, directory) for group_no, domain in config.as_es.items()]
    pool.starmap(layer2_config_group, inputs)



