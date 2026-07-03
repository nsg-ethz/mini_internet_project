from .config import *
from .subnet_config import *
from .helper import *
from multiprocessing import Pool


def install_key(cnt_name: str, group_directory: str):
    run_cmd(f"docker cp {group_directory}/id_rsa.pub {cnt_name}:/root/.ssh/authorized_keys > /dev/null")
    run_cmd(f"docker exec {cnt_name} bash -c \"kill -HUP \\$(cat /var/run/sshd.pid)\"",check=False)

def configure_ssh_group(group_no:int, domain: Domain, directory: Path):

    if isinstance(domain, AS):
        group_directory=f"{directory}/groups/g{group_no}"
        ssh_container=f"{group_no}_ssh"

        run_cmd(f"ssh-keygen -t rsa -b 4096 -C \"internal key group {group_no}\" -P \"\" -f \"groups/g{group_no}/id_rsa\" -q")
        run_cmd(f"docker cp {group_directory}/id_rsa {ssh_container}:/root/.ssh/id_rsa > /dev/null")
        run_cmd(f"docker cp {group_directory}/id_rsa.pub {ssh_container}:/root/.ssh/id_rsa.pub > /dev/null")

        run_cmd(f"docker cp {directory}/groups/authorized_keys {ssh_container}:/root/.ssh/authorized_keys > /dev/null")

        passwd = str(run_cmd(f"awk \"\\$1 == {group_no} {{ print \\$2 }}\" {directory}/groups/passwords.txt").stdout).strip()
        run_cmd(f"docker exec {ssh_container} bash -c \"printf \"root:{passwd}\" | chpasswd > /dev/null \"")
        run_cmd(f"docker exec {ssh_container} bash -c \"kill -HUP \\$(cat /var/run/sshd.pid)\"", check=False)

        # add file for vpn secret
        run_cmd(f"docker exec {ssh_container} bash -c \"touch /root/secret.txt\"")

        for name, router in domain.routers.items():
            router_cnt_name = f"{group_no}_{router.name}router"
            install_key(router_cnt_name,group_directory)

            for i, _ in enumerate(router.hosts):
                extra = f"{i}" if len(router.services) > 1 else ""
                hostl3_cnt_name=f"{group_no}_{router.name}host{extra}"
                install_key(hostl3_cnt_name,group_directory)

        for l2_name, l2_network in domain.l2_networks.items():

            for switch in l2_network.switches.values():
                switch_cnt_name = f"{group_no}_L2_{l2_name}_{switch.name}"
                install_key(switch_cnt_name,group_directory)
            
            for name, _ in l2_network.hosts.items():
                l2_host_cnt_name = f"{group_no}_L2_{l2_name}_{name}"
                install_key(l2_host_cnt_name,group_directory)

        
def configure_ssh(config: Topology, directory: Path):

    run_cmd("ssh-keygen -t rsa -b 4096 -C \"ta key\" -P \"\" -f \"groups/id_rsa\" -q")
    # We need to distribute the key to the TAs, so we make it readable.
    run_cmd("chmod +r groups/id_rsa")
    run_cmd("cp groups/id_rsa.pub groups/authorized_keys")

    pool = Pool(processes = get_num_threads())
    inputs = [(group_no,domain,directory) for group_no, domain in config.as_es.items()]
    pool.starmap(configure_ssh_group, inputs)
