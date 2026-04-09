from ..setup.helper import run_cmd
from ..setup.config import Topology
from .container_cleanup import container_cleanup
from .vpn_cleanup import vpn_cleanup

from pathlib import Path
import argparse

if __name__ == "__main__":
    script_dir = Path(__file__).resolve().parent.parent

    parser = argparse.ArgumentParser()
    parser.add_argument('-c', '--config', default=script_dir.joinpath("config"))
    parser.add_argument('-v', '--verbose', action='store_true', help='Enable verbose output')
    parser.add_argument('--hard_reset',action='store_true', help='Do a hard reset')
    args = parser.parse_args()

    topology = Topology.from_config(args)

    if args.hard_reset:
        run_cmd("docker rm -f $(docker ps -q) 2>/dev/null || echo \"No containers to remove\" ")

        # Delete virtual interfaces except for known system interfaces.
        interfaces = str(run_cmd("ip -o link show | awk -F': ' '{print $2}'").stdout).split()
        print("interfaces to delete:")
        for interface in interfaces:
            if interface.startswith(("en","lo","eth","docker0","virbr0")):
                pass
            else:
                print(interface)
                run_cmd(f"ip link delete {interface}",check=False)
        
        run_cmd("ip -all netns delete")

        if Path(f"{script_dir}/groups").is_dir():
            run_cmd(f"rm -rf {script_dir}/groups")

        run_cmd("docker system prune -f --volumes")
        run_cmd("service docker restart")

    else:
        container_cleanup(topology, script_dir)
        print("removed container")

        run_cmd("docker system prune -f")

        if Path("/var/run/netns").is_file():
            run_cmd("find /var/run/netns -xtype l -delete")


        interfaces = str(run_cmd("ip link | grep -E '(_c@|vpn|_l|_a|_b|veth)' | awk -F': ' '{print $2}' | cut -d'@' -f1 || true").stdout).split()

        for interface in interfaces:
            run_cmd(f"ip link delete {interface} || true")

        vpn_cleanup(topology, script_dir)

        if Path(f"{script_dir}/groups").is_dir():
            run_cmd(f"rm -rf {script_dir}/groups")

