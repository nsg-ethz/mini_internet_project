from .config import *
from .subnet_config import *
from .helper import run_cmd



def folder_setup(config: Topology, directory: Path):

    run_cmd(f"mkdir {directory}/groups")

    for group_no, domain in config.as_es.items():

        run_cmd(f"mkdir {directory}/groups/g{group_no}")

        if isinstance(domain, AS):

            for router_name, _ in domain.routers.items():

                location = f"{directory}/groups/g{group_no}/{router_name}"
                run_cmd(f"mkdir {location}")
                # router configs are saved periodically in frr.con
                run_cmd(f"touch {location}/frr.conf")
                run_cmd(f"cp config/daemons {location}/daemons")
                run_cmd(f"touch {location}/connectivity.txt")
                run_cmd(f"touch {location}/looking_glass.txt")
                run_cmd(f"touch {location}/looking_glass_json.txt")

        else:
            location = f"{directory}/groups/g{group_no}"
            run_cmd(f"touch {location}/frr.conf")
            run_cmd(f"touch {location}/looking_glass.txt")
            run_cmd(f"cp config/daemons {location}/daemons")

