from ..setup.config import *
from ..setup.helper import get_num_threads,run_cmd
from multiprocessing import Pool


def kill_container(name: str):
    run_cmd(f"docker kill {name} &>/dev/null")

def container_cleanup(config: Topology, directory: Path):

    pool = Pool(processes = get_num_threads())
    inputs = [(group_no,domain) for group_no, domain in config.as_es.items()]
    result = pool.starmap(cleanup_group, inputs)


    kill_container("DNS")
    kill_container("MEASUREMENT")
    kill_container("MATRIX")
    kill_container("WEB")
    kill_container("PROXY")
    kill_container("HISTORY")

    run_cmd("docker system prune -f --volumes")

    return


def cleanup_group(group_no:int, domain: Domain):
    
    if isinstance(domain, AS):

        kill_container(f"{group_no}_ssh")

        for router in domain.routers.values():

            kill_container(f"{group_no}_{router.name}router")           
            
            for i, _ in enumerate(router.hosts):
                extra = f"{i}" if len(router.services) > 1 else ""
                hostl3_cnt_name=f"{group_no}_{router.name}host{extra}"

                kill_container(hostl3_cnt_name)


        for l2_name, l2_network in domain.l2_networks.items():

            for switch in l2_network.switches.values():
                switch_cnt_name = f"{group_no}_L2_{l2_name}_{switch.name}"
                kill_container(switch_cnt_name)

            for name, _ in l2_network.hosts.items():
                l2_host_cnt_name = f"{group_no}_L2_{l2_network.name}_{name}"
                kill_container(l2_host_cnt_name)
    
    elif isinstance(domain, IXP):

        kill_container(f"{group_no}_IXP")
    
    return