from setup.config import Topology
from setup.container_setup import container_setup
from setup.save_configs import save_configs
from pathlib import Path
import subprocess, argparse

def run_cmd(cmd: str | list[str], check: bool = True) -> subprocess.CompletedProcess[str]:
    """Run a shell command and return the result.
    
    Args:
        cmd: Command as a string or list of arguments.
        check: If True, raise CalledProcessError on non-zero exit.
    
    Returns:
        CompletedProcess with stdout/stderr captured.
    
    Examples:
        run_cmd("sysctl net.ipv4.neigh.default.gc_thresh1=16384")
        run_cmd(["sysctl", "-w", "net.ipv4.ip_forward=1"])
    """
    if isinstance(cmd, str):
        return subprocess.run(cmd, shell=True, check=check, capture_output=True, text=True)
    return subprocess.run(cmd, check=check, capture_output=True, text=True)

    
if __name__ == "__main__":
    script_dir = Path(__file__).resolve().parent

    parser = argparse.ArgumentParser()
    parser.add_argument('-c', '--config', default=script_dir.joinpath("config"))
    parser.add_argument('-v', '--verbose', action='store_true', help='Enable verbose output')
    args = parser.parse_args()

    topology = Topology.from_config(args)

    save_configs(topology, script_dir)
    container_setup(topology, script_dir)


    # # Change size of ARP table necessary for large networks
    # # ARP: IP-to-MAC resolution
    # run_cmd("sysctl net.ipv4.neigh.default.gc_thresh1=16384") # the kernel begins to purge unused entries periodically
    # run_cmd("sysctl net.ipv4.neigh.default.gc_thresh2=32768") # more aggresive purging
    # run_cmd("sysctl net.ipv4.neigh.default.gc_thresh3=131072") # no new entries are allowed
    # # apply changes from sysctl.conf
    # run_cmd("sysctl -p")
    # # Increase the max number of running processes
    # run_cmd("sysctl kernel.pid_max=4194304")

    # print("hello")