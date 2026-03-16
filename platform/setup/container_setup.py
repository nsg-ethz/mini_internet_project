from .config import *
from config.subnet_config import *
from .helper import get_num_threads,get_docker_pid,run_cmd
from ipaddress import IPv4Interface
from multiprocessing import Pool
from pathlib import Path
import os
import docker
from docker.types import LogConfig,IPAMConfig,IPAMPool
#from docker.models.containers import Container

def container_setup(config: Topology, directory: Path):
    client = docker.from_env()
    print("container_setup starts...")
    
    #TODO read in the environments from the config
    os.environ["DOCKERHUB_PREFIX"] = config.environment["DOCKERHUB_PREFIX"]
    os.environ["DOCKER_TAG"] = config.environment["DOCKER_TAG"]
    os.environ["VPN_OBSERVER_SLEEP"] = config.environment["VPN_OBSERVER_SLEEP"]

    rpki_location=Path(f"{directory}/groups/rpki")
    krill_container_list_file=f"{rpki_location}/krill_containers.txt"
    routinator_container_list_file=f"{rpki_location}/routinator_containers.txt"
    

    all_containers: list[str] = []
    all_routinator_containers: list[str] = []
    all_krill_containers: list[str] = []


    subnet_ssh = IPv4Interface(subnet_ext_sshContainer(-1,"docker"))
    ipam_config_ssh = IPAMConfig(pool_configs=[IPAMPool(subnet=subnet_ssh.network.with_prefixlen)])
    client.networks.create(driver="bridge", ipam=ipam_config_ssh, name="ssh_bridge")

    pool = Pool(processes = get_num_threads())
    inputs = [(group_no,domain,directory,rpki_location) for group_no, domain in config.as_es.items()]
    result = pool.starmap(create_group, inputs)
    
    for group in result:
        all_containers += group[0]
        all_routinator_containers += group[1]
        all_krill_containers += group[2]
    
    with open(krill_container_list_file,"w+") as file:
        file.write("\n".join(all_krill_containers))
    
    with open(routinator_container_list_file,"w+") as file:
        file.write("\n".join(all_routinator_containers))

    with open(f"{directory}/groups/docker_pid.map","w+") as file:
        file.write("declare -A DOCKER_TO_PID=(")
        for container_name in all_containers:
            pid = get_docker_pid(container_name)
            file.write(f" [{container_name}]=\"{pid}\" ")
        file.write(")")

    client.close()



def create_group(group_no:int, domain: Domain, directory: Path, rpki_location: Path):
    client = docker.from_env()

    group_containers: list[str] = []
    routinator_containers: list[str] = []
    krill_containers: list[str] = []
    # create ssh network
    subnet_ssh_docker = IPv4Interface(subnet_sshContainer_groupContainer(group_no, -1, -1, "docker"))
    ipam_config_ssh_docker = IPAMConfig(pool_configs=[IPAMPool(subnet=subnet_ssh_docker.network.with_prefixlen)])
    client.networks.create(driver="bridge",internal=True,ipam=ipam_config_ssh_docker, name=f"{group_no}_ssh")
    
    lc = LogConfig(type=LogConfig.types.JSON, config={'max-size': '1g', "max-file": '3'})
    location = f"{directory}/groups/g{group_no}"
    

    if isinstance(domain, AS):

        # start ssh containers

        
        subnet_dns=IPv4Interface(subnet_router_DNS(group_no, "dns-group"))

        ssh_cnt_name = f"{group_no}_ssh"
        ssh_net_name = f"{group_no}_ssh"

        volumes_ssh = {f'{location}/goto.sh': {'bind': '/root/goto.sh', 'mode': 'rw'},
                f'{location}/save_configs.sh': {'bind': '/root/save_configs.sh', 'mode': 'rw'},
                f'{location}/restore_configs.sh': {'bind': '/root/restore_configs.sh', 'mode': 'rw'},
                f'{location}/restart_ospfd.sh': {'bind': '/root/restart_ospfd.sh', 'mode': 'rw'},
                f'{str(directory)}/config/ssh_welcome_message.txt': {'bind': '/etc/motd', 'mode': 'ro'},
                f'/etc/timezone': {'bind': '/etc/timezone', 'mode': 'ro'},
                f'/etc/localtime': {'bind': '/etc/localtime', 'mode': 'ro'}}

        client.containers.run(image=f"{os.environ["DOCKERHUB_PREFIX"]}ssh:{os.environ["DOCKER_TAG"]}",
                            name=f"{group_no}_ssh",tty=True, detach=True,cpu_count=2,pids_limit=100,
                            hostname=f"g{group_no}-proxy", cap_add=["NET_ADMIN"],log_config=lc,
                            network="bridge", ports={'22': group_no + 2000},
                            volumes=volumes_ssh)
        group_containers += [f"{group_no}_ssh"]

        subnet_ssh_ext_cont = IPv4Interface(subnet_ext_sshContainer(group_no,"sshContainer"))
        subnet_ssh_group_cont = IPv4Interface(subnet_sshContainer_groupContainer(group_no, -1, -1, "sshContainer"))

        # connect to the ssh container network and rename interface
        ssh_container = client.containers.get(ssh_cnt_name)
        client.networks.get(f"ssh_bridge").connect(container=ssh_container,ipv4_address=str(subnet_ssh_ext_cont.ip))
        ssh_container.exec_run("ip link set dev eth1 down")
        ssh_container.exec_run("ip link set dev eth1 name ssh")
        ssh_container.exec_run("ip link set dev ssh up")

        client.networks.get(ssh_net_name).connect(container=ssh_container,ipv4_address=str(subnet_ssh_group_cont.ip))
        client.containers.get(ssh_cnt_name).exec_run("ip link set dev eth2 down")
        client.containers.get(ssh_cnt_name).exec_run("ip link set dev eth2 name ssh_to_as")
        client.containers.get(ssh_cnt_name).exec_run("ip link set dev ssh_to_as up")


        # start l2 networks
        for l2_name, l2_network in domain.l2_networks.items():

            # start switches
            for switch in l2_network.switches:
                switch_cnt_name = f"{group_no}_L2_{l2_name}_{switch.name}"
                subnet_ssh_switch = str(IPv4Interface(subnet_sshContainer_groupContainer(group_no, -1, switch.bridge_id-1, "switch")).ip)
                netconf_ssh_switch = {ssh_net_name: client.api.create_endpoint_config(ipv4_address=subnet_ssh_switch)}

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
                
                client.containers.run(image=f"{os.environ["DOCKERHUB_PREFIX"]}switch:{os.environ["DOCKER_TAG"]}",
                                    name=switch_cnt_name, tty=True, detach=True, cpu_count=2, pids_limit=200,
                                    hostname=f"{switch.name}", cap_add=["ALL"], cap_drop=["SYS_RESOURCE"],
                                    log_config=lc, network=ssh_net_name, networking_config=netconf_ssh_switch, sysctls=sysctl_forward,
                                    volumes=volumes_switch, dns=[str(subnet_dns.ip)])
                group_containers += [switch_cnt_name]

                client.containers.get(switch_cnt_name).exec_run("ip link set dev eth0 down")
                client.containers.get(switch_cnt_name).exec_run("ip link set dev eth0 name ssh")
                client.containers.get(switch_cnt_name).exec_run("ip link set dev ssh up")
            
            # start l2 hosts
            for name, l2_host in l2_network.hosts.items():

                l2_host_cnt_name = f"{group_no}_L2_{l2_network.name}_{name}"
                subnet_ssh_host=str(IPv4Interface(subnet_sshContainer_groupContainer(group_no, -1, l2_host.l2_id, "L2-host")).ip)
                net_conf_ssh_host = {ssh_net_name: client.api.create_endpoint_config(ipv4_address=subnet_ssh_host)}

                l2_image = l2_host.container_name

                sysctl_host = {"net.ipv4.icmp_ratelimit": 0,
                            "net.ipv4.icmp_echo_ignore_broadcasts": 0,
                            "net.ipv6.conf.all.disable_ipv6": 0,
                            "net.ipv6.icmp.ratelimit": 0}
                
                volumes_l2host = {f'/etc/timezone': {'bind': '/etc/timezone', 'mode': 'ro'}, 
                                f'/etc/localtime': {'bind': '/etc/localtime', 'mode': 'ro'}}
                
                client.containers.run(image=f"{l2_image}", name=l2_host_cnt_name, tty=True, detach=True, cpu_count=2,
                                    pids_limit=100, hostname=f"{name}", cap_add=["NET_ADMIN"],
                                    log_config=lc, network=ssh_net_name, networking_config=net_conf_ssh_host, sysctls=sysctl_host,
                                    volumes=volumes_l2host, dns=[str(subnet_dns.ip)])
                group_containers += [l2_host_cnt_name]

                client.containers.get(l2_host_cnt_name).exec_run("ip link set dev eth0 down")
                client.containers.get(l2_host_cnt_name).exec_run("ip link set dev eth0 name ssh")
                client.containers.get(l2_host_cnt_name).exec_run("ip link set dev ssh up")
                # this disables the automatic docker dns between containers
                run_cmd(f"docker exec {l2_host_cnt_name} bash -c \"rc=\\$(sed \'s/127.0.0.11/{str(subnet_dns.ip)}/\' /etc/resolv.conf) && echo -e \\\"\\$rc\\\" > /etc/resolv.conf\"")
                
        
        for name, router in domain.routers.items():

            router_location = f"{directory}/groups/g{group_no}/{router.name}"
            
            router_cnt_name = f"{group_no}_{router.name}router"

            subnet_ssh_router=str(IPv4Interface(subnet_sshContainer_groupContainer(group_no, router.id, -1, "router")).ip)
            netconf_ssh_router = {ssh_net_name: client.api.create_endpoint_config(ipv4_address=subnet_ssh_router)}

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

            volumes_router = {f'{router_location}/looking_glass.txt': {'bind': '/home/looking_glass.txt', 'mode': 'rw'},
                            f'{router_location}/looking_glass_json.txt': {'bind': '/home/looking_glass_json.txt', 'mode': 'rw'},
                            f'{router_location}/daemons': {'bind': '/etc/frr/daemons', 'mode': 'rw'},
                            f'{router_location}/frr.conf': {'bind': '/etc/frr/frr.conf', 'mode': 'rw'},
                            f'{router_location}/wireguard/': {'bind': '/etc/wireguard/', 'mode': 'rw'},
                            f'/etc/timezone': {'bind': '/etc/timezone', 'mode': 'ro'}, 
                            f'/etc/localtime': {'bind': '/etc/localtime', 'mode': 'ro'}}
                
            client.containers.run(image=f"{os.environ["DOCKERHUB_PREFIX"]}router:{os.environ["DOCKER_TAG"]}",
                                    name=router_cnt_name, tty=True, detach=True, cpu_count=2, pids_limit=100,
                                    hostname=f"{router.name}_router", cap_add=["ALL"], cap_drop=["SYS_RESOURCE"],
                                    log_config=lc, network=ssh_net_name, networking_config=netconf_ssh_router, sysctls=sysctl_forward,
                                    volumes=volumes_router, dns=[str(subnet_dns.ip)],
                                    environment=[f"VPN_OBSERVER_SLEEP={os.environ["VPN_OBSERVER_SLEEP"]}"])
            group_containers += [router_cnt_name]

            client.containers.get(router_cnt_name).exec_run("ip link set dev eth0 down")
            client.containers.get(router_cnt_name).exec_run("ip link set dev eth0 name ssh")
            client.containers.get(router_cnt_name).exec_run("ip link set dev ssh up")
            # this disables the automatic docker dns between containers
            run_cmd(f"docker exec {router_cnt_name} bash -c \"rc=\\$(sed \'s/127.0.0.11/{str(subnet_dns.ip)}/\' /etc/resolv.conf) && echo -e \\\"\\$rc\\\" > /etc/resolv.conf\"")


            # start host l3

            for i, host in enumerate(router.hosts):

                subnet_ssh_host=str(IPv4Interface(subnet_sshContainer_groupContainer(group_no, router.id+i, -1, "L3-host")).ip)
                netconf_ssh_host = {ssh_net_name: client.api.create_endpoint_config(ipv4_address=subnet_ssh_host)}

                extra = f"{i}" if len(router.services) > 1 else ""
                hostl3_cnt_name=f"{group_no}_{router.name}host{extra}"
                
                sysctl_host = {"net.ipv4.icmp_ratelimit": 0,
                            "net.ipv4.icmp_echo_ignore_broadcasts": 0,
                            "net.ipv6.conf.all.disable_ipv6": 0,
                            "net.ipv6.icmp.ratelimit": 0}

                ports_host: dict[str, int] = {}
                labels_host: dict[str, str] = {}
                if host.type == HostType.KRILL:

                    with open(f'{directory}/groups/g{group_no}/krill/krill_token.txt') as file:
                        krill_token = file.read()
                        volumes_host = {f'{rpki_location}/tals': {'bind': '/var/krill/tals', 'mode': 'rw'},
                                        f'{rpki_location}/root.crt': {'bind': '/usr/local/share/ca-certificates/root.crt', 'mode': 'ro'},
                                        f'{location}/krill/data': {'bind': '/var/krill/data', 'mode': 'rw'},
                                        f'{location}/krill/krill.includesprivatekey.pem': {'bind': '/etc/ssl/certs/cert.includesprivatekey.pem', 'mode': 'ro'},
                                        f'{location}/krill/krill.crt': {'bind': '/var/krill/data/ssl/cert.pem', 'mode': 'ro'},
                                        f'{location}/krill/krill.key': {'bind': '/var/krill/data/ssl/key.pem', 'mode': 'ro'},
                                        f'{location}/krill/krill.conf': {'bind': '/var/krill/krill.conf', 'mode': 'ro'},
                                        f'{location}/krill/setup.sh': {'bind': '/home/setup.sh', 'mode': 'ro'},
                                        f'{str(directory)}/config/roas': {'bind': '/var/krill/roas', 'mode': 'ro'}}
                        environments_host = [f"KRILL_CLI_TOKEN={krill_token}"]
                        krill_containers += [f"{group_no} {hostl3_cnt_name}"]
                        ports_host["3080"] = 3080
                        labels_host["traefik.enable"] = "true"
                        labels_host["traefik.http.routers.krill.entrypoints"]="krill"

                elif host.type == HostType.ROUTINATOR:
                    volumes_host = {f'{rpki_location}/root.crt': {'bind': '/usr/local/share/ca-certificates/root.crt', 'mode': 'ro'},
                                    f'{rpki_location}/tals': {'bind': '/root/.rpki-cache/tals', 'mode': 'ro'},
                                    f'{directory}/groups/g{group_no}/rpki_exceptions.json': {'bind': '/root/rpki_exceptions.json', 'mode': 'rw'},
                                    f'{directory}/groups/g{group_no}/rpki_exceptions_autograder.json': {'bind': '/root/rpki_exceptions_autograder.json', 'mode': 'rw'}}
                    environments_host = []
                    routinator_containers += [f"{group_no} {hostl3_cnt_name}"]

                elif host.type == HostType.VPNSECRET:
                    volumes_host = {f'{directory}/config/vpnsecret/': {'bind': '/server/', 'mode': 'ro'}}

                else:
                    volumes_host = {}
                    environments_host = []
                
                volumes_host.update({f'/etc/timezone': {'bind': '/etc/timezone', 'mode': 'ro'}, 
                                                    f'/etc/localtime': {'bind': '/etc/localtime', 'mode': 'ro'}})
                    
            
                client.containers.run(image=f"{host.container_name}", name=hostl3_cnt_name, tty=True, detach=True, cpu_count=2,
                                    pids_limit= 800 if host.type == HostType.KRILL else 100, hostname=f"{name}", cap_add=["NET_ADMIN"], ports=ports_host, labels=labels_host,
                                    log_config=lc, network=ssh_net_name, networking_config=netconf_ssh_host, sysctls=sysctl_host,
                                    volumes=volumes_host, dns=[str(subnet_dns.ip)], environment=environments_host)
                group_containers += [hostl3_cnt_name]

                client.containers.get(hostl3_cnt_name).exec_run("ip link set dev eth0 down")
                client.containers.get(hostl3_cnt_name).exec_run("ip link set dev eth0 name ssh")
                client.containers.get(hostl3_cnt_name).exec_run("ip link set dev ssh up")
                # this disables the automatic docker dns between containers
                run_cmd(f"docker exec {hostl3_cnt_name} bash -c \"rc=\\$(sed \'s/127.0.0.11/{str(subnet_dns.ip)}/\' /etc/resolv.conf) && echo -e \\\"\\$rc\\\" > /etc/resolv.conf\"")
            
                if host.type == HostType.KRILL:
                    client.networks.get("bridge").connect(container=hostl3_cnt_name)

    elif isinstance(domain, IXP):
        
        ixp_cnt_name = f"{group_no}_IXP"

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

        volumes_ixp = {f'{location}/daemons': {'bind': '/etc/frr/daemons'},
                       f'{location}/frr.conf': {'bind': '/etc/frr/frr.conf', 'mode': 'rw'},
                       f'{location}/looking_glass.txt': {'bind': '/home/looking_glass.txt', 'mode': 'rw'},
                       f'/etc/timezone': {'bind': '/etc/timezone', 'mode': 'ro'}, 
                       f'/etc/localtime': {'bind': '/etc/localtime', 'mode': 'ro'}}
                
        client.containers.run(image=f"{os.environ["DOCKERHUB_PREFIX"]}ixp:{os.environ["DOCKER_TAG"]}",
                                    name=ixp_cnt_name, tty=True, detach=True, cpu_count=2, pids_limit=200,
                                    hostname=f"{group_no}_IXP", cap_add=["ALL"], cap_drop=["SYS_RESOURCE"],
                                    log_config=lc, network='none', sysctls=sysctl_forward, volumes=volumes_ixp)
        group_containers += [ixp_cnt_name]

    print(f"Group {group_no}: {len(group_containers)} containers created!")

    client.close()
    return (group_containers,routinator_containers,krill_containers)

