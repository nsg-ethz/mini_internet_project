# import docker
import argparse
import subprocess
import csv
from pathlib import Path

class Domain:
    id: int

    def __init__(self, config: list[str]) -> None:
        self.id = int(config[0])

    @staticmethod
    def from_config(config: list[str]) -> "Domain":
        if config[1] == "AS":
            return AS(config)
        elif config[1] == "IXP":
            return IXP(config)
        else:
            raise ValueError(f"Unknown domain type: {config[1]}")
            

class IXP(Domain):
    as_id: int

class AS(Domain):
    as_id: int

class Topology:
    as_es: list[Domain]

def parse_configs(path: Path) -> Topology:

    with open(path.joinpath("AS_config.txt"), 'r') as f:
        # Specify the tab delimiter and quoting behavior
        as_level_config = csv.reader(f, delimiter='\t')

    as_es: list[Domain] = [Domain(domain_config) for domain_config in as_level_config]


    return Topology()



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
    args = parser.parse_args()

    parse_configs(args.config)

    # Change size of ARP table necessary for large networks
    # ARP: IP-to-MAC resolution
    run_cmd("sysctl net.ipv4.neigh.default.gc_thresh1=16384") # the kernel begins to purge unused entries periodically
    run_cmd("sysctl net.ipv4.neigh.default.gc_thresh2=32768") # more aggresive purging
    run_cmd("sysctl net.ipv4.neigh.default.gc_thresh3=131072") # no new entries are allowed
    # apply changes from sysctl.conf
    run_cmd("sysctl -p")
    # Increase the max number of running processes
    run_cmd("sysctl kernel.pid_max=4194304")

    print("hello")