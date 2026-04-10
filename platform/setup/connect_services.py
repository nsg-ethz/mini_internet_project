from .config import *
from .subnet_config import *
from .helper import run_cmd, connect_two_interfaces
import os
from ipaddress import IPv4Interface

def connect_measurement(group_no: int, name: str):
    cnt_1 = "MEASUREMENT"
    intf_1 = f"group{group_no}"
    cnt_2 = f"{group_no}_{name}router"
    intf_2 = f"measurement_{group_no}"
    pid_1, _ = connect_two_interfaces(cnt_1,intf_1,cnt_2,intf_2,None)
    subnet_grp = subnet_group(group_no)

    ip_meas = str(IPv4Interface(subnet_router_MEASUREMENT(group_no,"group")).ip)
    subnet_meas = subnet_router_MEASUREMENT(group_no,"measurement")

    run_cmd(f"ip netns exec {pid_1} ip addr add {subnet_meas} dev {intf_1}")
    run_cmd(f"ip netns exec {pid_1} ip route add default via {ip_meas} metric {group_no}")
    run_cmd(f"ip netns exec {pid_1} ip route add {subnet_grp} via {ip_meas}")


def connect_matrix(group_no: int, name: str):
    cnt_1 = "MATRIX"
    intf_1 = f"group_{group_no}"
    cnt_2 = f"{group_no}_{name}router"
    intf_2 = f"matrix_{group_no}"
    pid_1, _ = connect_two_interfaces(cnt_1,intf_1,cnt_2,intf_2,None)
    subnet_grp = subnet_group(group_no)

    ip_matrix = str(IPv4Interface(subnet_router_MATRIX(group_no,"group")).ip)
    subnet_matrix = subnet_router_MATRIX(group_no,"matrix")

    run_cmd(f"ip netns exec {pid_1} ip addr add {subnet_matrix} dev {intf_1}")
    run_cmd(f"ip netns exec {pid_1} ip route add default via {ip_matrix} metric {group_no}")
    run_cmd(f"ip netns exec {pid_1} ip route add {subnet_grp} via {ip_matrix}")


def connect_dns(group_no: int, name: str):
    cnt_1 = "DNS"
    intf_1 = f"group_{group_no}"
    cnt_2 = f"{group_no}_{name}router"
    intf_2 = f"dns_{group_no}"
    pid_1, _ = connect_two_interfaces(cnt_1,intf_1,cnt_2,intf_2,None)
    subnet_grp = subnet_group(group_no)

    ip_dns = str(IPv4Interface(subnet_router_DNS(group_no,"group")).ip)
    subnet_dns = subnet_router_DNS(group_no,"dns-group")

    run_cmd(f"ip netns exec {pid_1} ip addr add {subnet_dns} dev {intf_1}")
    run_cmd(f"ip netns exec {pid_1} ip route add {subnet_grp} via {ip_dns}")

def connect_dns_measurement():
    cnt_1 = "DNS"
    intf_1 = f"measurement"
    cnt_2 = f"MEASUREMENT"
    intf_2 = f"dns"
    pid_1, pid_2 = connect_two_interfaces(cnt_1,intf_1,cnt_2,intf_2,None)

    subnet_dns_meas = subnet_router_DNS(-1,"dns-measurement")
    subnet_meas = subnet_router_DNS(-1, "measurement")

    run_cmd(f"ip netns exec {pid_1} ip addr add {subnet_dns_meas} dev {intf_1}")
    run_cmd(f"ip netns exec {pid_2} ip addr add {subnet_meas} dev {intf_2}")


def connect_services(config: Topology, directory: Path):
    import docker
    os.environ["DOCKERHUB_PREFIX"] = config.environment["DOCKERHUB_PREFIX"]
    os.environ["DOCKER_TAG"] = config.environment["DOCKER_TAG"]
    os.environ["MATRIX_FREQUENCY"] = config.environment["MATRIX_FREQUENCY"]
    os.environ["MATRIX_CONCURRENT_PINGS"] = config.environment["MATRIX_CONCURRENT_PINGS"]
    os.environ["MATRIX_PING_FLAGS"] = config.environment["MATRIX_PING_FLAGS"]
    os.environ["MATRIX_PAUSE_AFTER_START"] = config.environment["MATRIX_PAUSE_AFTER_START"]

    client = docker.from_env()
    services: set[Service] = set()
    for domain in config.as_es.values():
        for router in domain.routers.values():
            services = services.union(router.services)
    
    
    containers: list[str] = []

    if Service.MEASUREMENT in services:

        subnet_dns_measurement = str(IPv4Interface(subnet_router_DNS(-1, "dns-measurement")).ip)
        subnet_ssh_measurement = IPv4Interface(subnet_ext_sshContainer(-1, "MEASUREMENT"))
        ssh_bridge = "ssh_bridge"

        sysctl_measurement = {"net.ipv4.ip_forward": 0, "net.ipv4.icmp_ratelimit": 0}

        volumes_measurement =  { f'{directory}/config/measurement_welcome_message.txt': {'bind': '/etc/motd', 'mode': 'ro'},
                                f'/etc/timezone': {'bind': '/etc/timezone', 'mode': 'ro'},
                                f'/etc/localtime': {'bind': '/etc/localtime', 'mode': 'ro'}}

        client.containers.run(image=f"{os.environ["DOCKERHUB_PREFIX"]}measurement:{os.environ["DOCKER_TAG"]}",
                   name=f"MEASUREMENT", tty=True, detach=True, cpu_count=2, pids_limit=100,
                   hostname=f"MEASUREMENT", network="bridge", ports={'22': 2099}, cap_add=["NET_ADMIN"],
                   dns=[subnet_dns_measurement], sysctls=sysctl_measurement, volumes=volumes_measurement)
        
        containers += ["MEASUREMENT"]

        client.networks.get(ssh_bridge).connect(container="MEASUREMENT",ipv4_address=str(subnet_ssh_measurement.ip))

        meas_cnt = client.containers.get("MEASUREMENT")
        meas_cnt.exec_run("ip link set dev eth1 down")
        meas_cnt.exec_run("ip link set dev eth1 name ssh")
        meas_cnt.exec_run("ip link set dev ssh up")

        run_cmd(f"docker cp {directory}/groups/authorized_keys MEASUREMENT:/root/.ssh/authorized_keys > /dev/null")
        passwd = str(run_cmd("openssl rand -hex 8").stdout)
        with open(f"{directory}/groups/ssh_measurement.txt","a+") as file:
            file.write(passwd)
        meas_cnt.exec_run(f"printf \"root:{passwd}\" | chpasswd")


    if Service.MATRIX in services:
        matrix_conf_dir = f"{directory}/groups/matrix/"
        run_cmd(f"mkdir -p {matrix_conf_dir}")
        run_cmd(f"touch {matrix_conf_dir}/destination_ips.txt")
        run_cmd(f"touch {matrix_conf_dir}/connectivity.txt")
        run_cmd(f"touch {matrix_conf_dir}/stats.txt")

        sysctl_matrix = {"net.ipv4.ip_forward": 0, "net.ipv4.icmp_ratelimit": 0}

        volumes_matrix =  { f'{matrix_conf_dir}/destination_ips.txt': {'bind': '/home/destination_ips.txt', 'mode': 'rw'},
                            f'{matrix_conf_dir}/connectivity.txt': {'bind': '/home/connectivity.txt', 'mode': 'rw'},
                            f'{matrix_conf_dir}/stats.txt': {'bind': '/home/stats.txt', 'mode': 'rw'},
                            f'/etc/timezone': {'bind': '/etc/timezone', 'mode': 'ro'},
                            f'/etc/localtime': {'bind': '/etc/localtime', 'mode': 'ro'}}

        environment_matrix = [f"UPDATE_FREQUENCY={os.environ["MATRIX_FREQUENCY"]}",
                              f"CONCURRENT_PINGS={os.environ["MATRIX_CONCURRENT_PINGS"]}",
                              f"PING_FLAGS={os.environ["MATRIX_PING_FLAGS"]}"]

        client.containers.run(image=f"{os.environ["DOCKERHUB_PREFIX"]}matrix:{os.environ["DOCKER_TAG"]}",
                   name=f"MATRIX", tty=True, detach=True, hostname=f"MATRIX", privileged=True,
                   sysctls=sysctl_matrix, volumes=volumes_matrix,environment=environment_matrix)

        containers += ["MATRIX"]

        if os.environ["MATRIX_PAUSE_AFTER_START"].strip().lower() == "true":
            run_cmd("docker pause MATRIX")

    if Service.DNS in services:

        subnet_router_dns = subnet_router_DNS(-1, "dns")

        sysctl_dns = {"net.ipv4.ip_forward": 0}

        volumes_dns =  { f'{directory}/groups/dns/group_config': {'bind': '/etc/bind/group_config', 'mode': 'ro'},
                            f'{directory}/groups/dns/zones': {'bind': '/etc/bind/zones', 'mode': 'ro'},
                            f'{directory}/groups/dns/named.conf.local': {'bind': '/etc/bind/named.conf.local', 'mode': 'ro'},
                            f'{directory}/groups/dns/named.conf.options': {'bind': '/etc/bind/named.conf.options', 'mode': 'ro'},
                            f'/etc/timezone': {'bind': '/etc/timezone', 'mode': 'ro'},
                            f'/etc/localtime': {'bind': '/etc/localtime', 'mode': 'ro'}}

        client.containers.run(image=f"{os.environ["DOCKERHUB_PREFIX"]}dns:{os.environ["DOCKER_TAG"]}",
                   name=f"DNS", tty=True, detach=True, hostname=f"DNS", network="bridge", privileged=True,
                   sysctls=sysctl_dns, volumes=volumes_dns)
        
        containers += ["DNS"]

        cnt_dns = client.containers.get("DNS")
        cnt_dns.exec_run("ip link add name dns type dummy")
        cnt_dns.exec_run(f"ip addr add {subnet_router_dns} dev dns")
        cnt_dns.exec_run("ip link set dns up")

    
    with open(f"{directory}/groups/docker_pid.map","r") as file:
        content = file.read().removeprefix("declare -A DOCKER_TO_PID=(").removesuffix(")")

        for element in content.split():
            containers += [element.strip("[").split("]")[0]]

    with open(f"{directory}/groups/docker_pid.map","w+") as file:
        file.write("declare -A DOCKER_TO_PID=(")
        for container_name in containers:
            container_id = client.containers.get(container_name).id
            api = docker.APIClient(base_url='unix://var/run/docker.sock')
            pid = api.inspect_container(container_id)["State"]["Pid"]
            file.write(f" [{container_name}]=\"{pid}\" ")
        file.write(")")
    

    for group_no, domain in config.as_es.items():
        
        if isinstance(domain,AS):

            if Service.MEASUREMENT in services:
                with open(f"{directory}/groups/g{group_no}/id_rsa.pub") as file:
                    pubkey = file.read()

                    sshifname=f"ssh_group{group_no}"
                    ssh_subnet = IPv4Interface(subnet_sshContainer_groupContainer(group_no, -1, -1, "MEASUREMENT"))

                    client.networks.get(f"{group_no}_ssh").connect(container="MEASUREMENT",ipv4_address=str(ssh_subnet.ip))
                    ifname = str(run_cmd(f"docker exec MEASUREMENT ip -oneline addr show | grep {ssh_subnet.ip} | cut -f 2 -d ' '").stdout)
                    
                    meas_cnt = client.containers.get("MEASUREMENT")
                    meas_cnt.exec_run(f"ip link set dev {ifname} down")
                    meas_cnt.exec_run(f"ip link set dev {ifname} name {sshifname}")
                    meas_cnt.exec_run(f"ip link set dev {sshifname} up")
                    run_cmd(f"docker exec -d MEASUREMENT bash -c \"echo \'{pubkey}\' >> /root/.ssh/authorized_keys\"")


            for name, router in domain.routers.items():

                if Service.MEASUREMENT in router.services:
                    connect_measurement(group_no, name)
                
                if Service.MATRIX_TARGET in router.services:
                    matrix_conf_dir = f"{directory}/groups/matrix/"
                    dest_ip = str(IPv4Interface(subnet_host_router(group_no, router.id, "host")).ip)
                    with open(f"{matrix_conf_dir}/destination_ips.txt", "a+") as file:
                        file.write(f"{group_no} {dest_ip}\n")

                if Service.MATRIX in router.services:
                    connect_matrix(group_no, name)

                if Service.DNS in router.services:
                    connect_dns(group_no, name)

    # connect measurement to dns
    if Service.DNS in services:
        connect_dns_measurement()

    client.close()
