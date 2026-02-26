from .config import *
from config.subnet_config import *
from .helper import run_cmd
import docker 



def history_setup(config: Topology, directory: Path):
    
    client = docker.from_env()

    datadir=f"{directory}/groups"
    historydir=f"{directory}/history"
    run_cmd(f"mkdir -p {historydir}")
    matrixdir=f"{datadir}/matrix"

    env = config.environment

    if env["HISTORY_ENABLED"].strip().lower() == "true":
        

        history_environment = ["OUTPUT_DIR=/home/history", f"MATRIX_DIR=/home/matrix",
                            f"UPDATE_FREQUENCY={env["HISTORY_UPDATE_FREQUENCY"]}", 
                            f"TIMEOUT={env["HISTORY_TIMEOUT"]}", f"GIT_USER={env["HISTORY_GIT_USER"]}",
                            f"GIT_EMAIL={env["HISTORY_GIT_EMAIL"]}", f"GIT_URL={env["HISTORY_GIT_URL"]}",
                            f"GIT_BRANCH={env["HISTORY_GIT_BRANCH"]}", f"FORGET_BINARIES={env["HISTORY_FORGET_BINARIES"]}"] 
        
        history_volumes = {'/var/run/docker.sock': {"bind": "/var/run/docker.sock", "mode": "rw"},
                            f'{historydir}': {"bind": "/home/history", "mode": "rw"},
                            f'{matrixdir}': {"bind": "/home/matrix", "mode": "rw"}}

        client.containers.run(image=f"{env["DOCKERHUB_PREFIX"]}history:{env["DOCKER_TAG"]}",
                            network="bridge", name="HISTORY", hostname="HISTORY", tty=True, detach=True,
                            environment=history_environment, volumes=history_volumes)

        if env["HISTORY_PAUSE_AFTER_START"].strip().lower() == "true":
            run_cmd("docker pause HISTORY")