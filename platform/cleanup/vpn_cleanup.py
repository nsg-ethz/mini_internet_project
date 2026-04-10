import docker
from ..setup.config import *
from ..setup.helper import get_num_threads,run_cmd
from multiprocessing import Pool


def delete_interface(as_no: int, router_id: int, router_name: str, directory: Path):
    path_to_file=f"{directory}/groups/g{as_no}/{router_name}/wireguard"
    listen_port= 10000 + as_no + 1000 * router_id
    
    interface_up = str(run_cmd(f"docker exec {as_no}_{router_name}router sh -c \"ip link show vpn up > /dev/null 2>&1 && echo 1 || echo 0\"",check=False).stdout)
    if interface_up == "1":
        client = docker.from_env()
        container = client.containers.get(f"{as_no}_{router_name}router")
        api = docker.APIClient(base_url='unix://var/run/docker.sock')
        pid = api.inspect_container(container.id)["State"]["Pid"]
        run_cmd(f"nsenter --net=/proc/{pid}/ns/net ip link del vpn")

    interface_up = str(run_cmd(f"docker exec {as_no}_{router_name}router sh -c \"ip link show vpn up > /dev/null 2>&1 && echo 1 || echo 0\"",check=False).stdout)
    if interface_up == "1":
        run_cmd(f"rm {path_to_file}/*")

    run_cmd(f"ufw delete allow {listen_port} > /dev/null")
    
    return


def vpn_cleanup(config: Topology, directory: Path):
    pool = Pool(processes = get_num_threads())
    inputs = [(group_no,domain, directory) for group_no, domain in config.as_es.items()]
    result = pool.starmap(vpn_cleanup_group, inputs)
    
    return



def vpn_cleanup_group(group_no:int, domain: Domain, directory: Path):

    if isinstance(domain, AS):
        for router in domain.routers.values():
            print(f"Deleting wg interface {group_no}-{router.name}")
            delete_interface(group_no, router.id, router.name, directory)

    return