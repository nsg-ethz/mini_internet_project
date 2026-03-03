from .config import *
from config.subnet_config import *
from .helper import run_cmd, clean_ctn_netns
from .connect_internal import *
from .connect_external import *
from .connect_services import connect_services
from .website_setup import website_setup
from .history_setup import history_setup
import docker


def only_start(config: Topology, directory: Path):

    client = docker.from_env()

    containers: list[str] = []
    with open(f"{directory}/groups/docker_pid.map","r") as file:
        content = file.read().removeprefix("declare -A DOCKER_TO_PID=(").removesuffix(")")

        for element in content.split():
            containers += [element.strip("[").split("]")[0]]

    for container_name in containers:
            container_id = client.containers.get(container_name).id
            api = docker.APIClient(base_url='unix://var/run/docker.sock')
            pid = api.inspect_container(container_id)["State"]["Pid"]
            clean_ctn_netns(int(pid))
    
    for cont_name in containers:
        client.containers.get(cont_name).restart()
    
    with open(f"{directory}/groups/docker_pid.map","w+") as file:
        file.write("declare -A DOCKER_TO_PID=(")
        for container_name in containers:
            container_id = client.containers.get(container_name).id
            api = docker.APIClient(base_url='unix://var/run/docker.sock')
            pid = api.inspect_container(container_id)["State"]["Pid"]
            file.write(f" [{container_name}]=\"{pid}\" ")
        file.write(")")



    print("\nstarting connect_l3_host_router\n")
    connect_l3_host_router(config, directory)

    print("\nstarting connect_l2_network\n")
    connect_l2_network(config, directory)

    print("\nstarting connect_l3_network\n")
    connect_l3_network(config, directory)

    print("\nstarting connect_external_router\n")
    connect_external_router(config, directory)

    run_cmd(f"{directory}/setup/restart_container.sh measurement")
    run_cmd(f"{directory}/setup/restart_container.sh dns")
    run_cmd(f"{directory}/setup/restart_container.sh matrix")
    run_cmd(f"{directory}/setup/restart_container.sh web")


    # reload dns server config  
    run_cmd("docker kill --signal=HUP DNS")

    print("\nApplying hijacks\n")

    run_cmd(f"./setup/hijack_config.py {directory}")

    print("Waiting 60sec for BGP messages to propagate...")
    time.sleep(60)

    print("Refreshing selected advertisements: ")
    run_cmd(f"./setup/bgp_clear.sh {directory}")
