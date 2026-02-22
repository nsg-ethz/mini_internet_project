from setup.config import Topology
from setup.goto_scripts import goto_scripts
from setup.save_configs import save_configs
from setup.container_setup import container_setup
from setup.vpn_config import vpn_config
from pathlib import Path
import argparse

    
if __name__ == "__main__":
    script_dir = Path(__file__).resolve().parent

    parser = argparse.ArgumentParser()
    parser.add_argument('-c', '--config', default=script_dir.joinpath("config"))
    parser.add_argument('-v', '--verbose', action='store_true', help='Enable verbose output')
    args = parser.parse_args()

    topology = Topology.from_config(args)

    goto_scripts(topology, script_dir)
    save_configs(topology, script_dir)
    container_setup(topology, script_dir)
    vpn_config(topology, script_dir)

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