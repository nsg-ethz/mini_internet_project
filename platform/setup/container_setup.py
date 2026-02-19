from .config import *
from ..config.subnet_config import *
from ipaddress import IPv4Interface
from pathlib import Path
import os
import docker
from docker.types import LogConfig

def container_setup(config: Topology, directory: Path):
    client = docker.from_env()
    print("container_setup starts...")

    subnet_ssh = IPv4Interface(subnet_ext_sshContainer(-1,"docker"))
    client.network.create(driver="bridge", subnet=subnet_ssh.network.with_prefixlen, name="ssh_bridge")

    for group_no,domain in config.as_es.items():
       
        # create ssh network
        subnet_ssh_docker = IPv4Interface(subnet_sshContainer_groupContainer(f"{group_no}", -1, -1, "docker"))
        client.network.create(driver="bridge",internal=True,subnet=subnet_ssh_docker.network.with_prefixlen, name=f"{group_no}_ssh")
        

        if isinstance(domain, AS):

            # start ssh containers

            location = f"{directory}/groups/g{group_no}"
            subnet_dns=IPv4Interface(subnet_router_DNS(f"{group_no}", "dns-group"))

            ssh_cnt_name = f"{group_no}_ssh"
            ssh_net_name = f"{group_no}_ssh"

            lc = LogConfig(type=LogConfig.types.JSON, config={'max-size': '1g', "max-file": '3'})

            volumes_ssh = {f'{location}/goto.sh': {'bind': '/root/goto.sh', 'mode': 'rw'},
                       f'{location}/save_configs.sh': {'bind': '/root/save_configs.sh', 'mode': 'rw'},
                       f'{location}/restore_configs.sh': {'bind': '/root/restore_configs.sh', 'mode': 'rw'},
                       f'{location}/restore_ospfd.sh': {'bind': '/root/restore_ospfd.sh', 'mode': 'rw'},
                       f'{str(directory)}/config/ssh_welcome_message.txt': {'bind': '/etc/motd', 'mode': 'ro'},
                       f'/etc/timezone': {'bind': '/etc/timezone', 'mode': 'ro'},
                       f'/etc/localtime': {'bind': '/etc/localtime', 'mode': 'ro'}}

            client.container.run(image=f"{os.environ["DOCKERHUB_PREFIX"]}ssh:{os.environ["DOCKERHUB_TAG"]}",
                                 name=f"{group_no}_ssh",tty=True, detach=True,cpu_count=2,pids_limit=100,
                                 hostname=f"g{group_no}-proxy", cap_add=["NET_ADMIN"],log_config=lc,
                                 network="bridge", ports={(group_no + 2000):22},
                                 volumes=volumes_ssh)
    
            subnet_ssh_ext_cont = IPv4Interface(subnet_ext_sshContainer(0,"sshContainer"))
            subnet_ssh_group_cont = IPv4Interface(subnet_sshContainer_groupContainer(f"{group_no}", -1, -1, "sshContainer"))

            # connect to the ssh container network and rename interface
            ssh_container = client.containers.get(ssh_cnt_name)
            client.networks.get(f"ssh_bridge").connect(container=ssh_container,ip=str(subnet_ssh_ext_cont.ip))
            ssh_container.exec_run("ip link set dev eth1 down")
            ssh_container.exec_run("ip link set dev eth1 name ssh")
            ssh_container.exec_run("ip link set dev ssh up")

            client.networks.get(ssh_net_name).connect(container=ssh_container,ip=str(subnet_ssh_group_cont.ip))
            client.containers.get(ssh_cnt_name).exec_run("ip link set dev eth2 down")
            client.containers.get(ssh_cnt_name).exec_run("ip link set dev eth2 name ssh_to_as")
            client.containers.get(ssh_cnt_name).exec_run("ip link set dev ssh_to_as up")


            # start l2 networks
            for name, l2_network in domain.l2_networks.items():

                # start switches
                for switch in l2_network.switches:
                    switch_cnt_name = f"{group_no}_L2_{name}_{switch.name}"
                    subnet_ssh_switch = subnet_sshContainer_groupContainer(f"{group_no}", -1, switch.bridge_id, "switch")
                    sysctl_forward = {"net.ipv4.ip_forward": 1,
                              "net.ipv4.icmp_ratelimit": 0,
                              "net.ipv4.fib_multipath_hash_policy": 1,
                              "net.ipv4.conf.all.rp_filter": 0,
                              "net.ipv4.conf.default.rp_filter": 0,
                              "net.ipv4.conf.lo.rp_filter": 0,
                              "net.ipv4.icmp_echo_ignore_broadcasts": 0,
                              "net.ipv6.conf.all.disable_ipv6": 0,
                              "net.ipv6.conf.all.forwarding": 1,
                              "net.ipv6.icmp.ratelimit": 0}
                    
                    volumes_switch = {f'/etc/timezone': {'bind': '/etc/timezone', 'mode': 'ro'}, 
                                      f'/etc/localtime': {'bind': '/etc/localtime', 'mode': 'ro'}}
                    
                    client.container.run(image=f"{os.environ["DOCKERHUB_PREFIX"]}switch:{os.environ["DOCKERHUB_TAG"]}",
                                         name=switch_cnt_name, tty=True, detach=True, cpu_count=2, pids_limit=1024,
                                         hostname=f"{switch.name}", cap_add=["ALL"], cap_drop=["SYS_RESOURCE"],
                                         log_config=lc, network=ssh_net_name, ip=subnet_ssh_switch, sysctls=sysctl_forward,
                                         volumes=volumes_switch, dns=str(subnet_dns.ip))
                    
                    client.containers.get(switch_cnt_name).exec_run("ip link set dev eth0 down")
                    client.containers.get(switch_cnt_name).exec_run("ip link set dev name ssh")
                    client.containers.get(switch_cnt_name).exec_run("ip link set dev ssh up")
                
                # start l2 hosts
                for name, l2_host in l2_network.hosts.items():

                    l2_host_cnt_name = f"{group_no}_L2_{l2_network.name}_{name}"

                    subnet_ssh_host=subnet_sshContainer_groupContainer(f"{group_no}", -1, l2_host[0], "L2-host")

                    l2_image = l2_host[1].container_name

                    sysctl_host = {"net.ipv4.icmp_ratelimit": 0,
                                   "net.ipv4.icmp_echo_ignore_broadcasts": 0,
                                   "net.ipv6.conf.all.disable_ipv6": 0,
                                   "net.ipv6.icmp.ratelimit": 0}
                    
                    volumes_l2host = {f'/etc/timezone': {'bind': '/etc/timezone', 'mode': 'ro'}, 
                                      f'/etc/localtime': {'bind': '/etc/localtime', 'mode': 'ro'}}
                    
                    client.container.run(image=f"{l2_image}", name=l2_host_cnt_name, tty=True, detach=True, cpu_count=2,
                                         pids_limit=100, hostname=f"{name}", cap_add=["NET_ADMIN"],
                                         log_config=lc, network=ssh_net_name, ip=subnet_ssh_host, sysctls=sysctl_host,
                                         volumes=volumes_l2host, dns=str(subnet_dns.ip))
                    
                    client.containers.get(l2_host_cnt_name).exec_run("ip link set dev eth0 down")
                    client.containers.get(l2_host_cnt_name).exec_run("ip link set dev eth0 name ssh")
                    client.containers.get(l2_host_cnt_name).exec_run("ip link set dev ssh up")
                    
            
            for name, router in domain.routers.items():
                

