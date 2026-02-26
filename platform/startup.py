from setup.config import Topology
from setup.rpki_config import rpki_config
from setup.goto_scripts import goto_scripts
from setup.save_configs import save_configs
from setup.container_setup import container_setup
from setup.vpn_config import vpn_config
from setup.connect_internal import *
from setup.connect_external import *
from setup.configure_ssh import configure_ssh
from setup.connect_services import connect_services
from setup.layer2_config import layer2_config
from setup.router_config import router_config
from setup.rpki_setup import rpki_setup
from setup.website_setup import website_setup
from setup.history_setup import history_setup

from pathlib import Path
import argparse
import time
    
if __name__ == "__main__":
    script_dir = Path(__file__).resolve().parent

    parser = argparse.ArgumentParser()
    parser.add_argument('-c', '--config', default=script_dir.joinpath("config"))
    parser.add_argument('-v', '--verbose', action='store_true', help='Enable verbose output')
    args = parser.parse_args()

    topology = Topology.from_config(args)

    print("\n\nstarting rpki_config\n\n")
    rpki_config(topology, script_dir)

    print("\n\nstarting goto_scripts\n\n")
    goto_scripts(topology, script_dir)

    print("\n\nstarting save_configs\n\n")
    save_configs(topology, script_dir)

    print("\n\nstarting container_setup\n\n")
    container_setup(topology, script_dir)

    print("\n\nstarting vpn_config\n\n")
    vpn_config(topology, script_dir)

    print("\n\nstarting connect_l3_host_router\n\n")
    connect_l3_host_router(topology,script_dir)

    print("\n\nstarting connect_l2_network\n\n")
    connect_l2_network(topology, script_dir)

    print("\n\nstarting connect_l3_network\n\n")
    connect_l3_network(topology,script_dir)

    print("\n\nstarting connect_external_router\n\n")
    connect_external_router(topology,script_dir)

    print("\n\nstarting configure_ssh\n\n")
    configure_ssh(topology,script_dir)

    print("\n\nstarting connect_services\n\n")
    connect_services(topology,script_dir)

    print("\n\nstarting layer2_config\n\n")
    layer2_config(topology,script_dir)

    print("\n\nstarting router_config\n\n")
    router_config(topology,script_dir)

    print("Waiting 60sec for RPKI CA and proxy to startup..")
    time.sleep(60)

    print("\n\nstarting rpki_setup\n\n")
    rpki_setup(topology,script_dir)

    print("\n\nstarting website_setup\n\n")
    website_setup(topology,script_dir)

    print("\n\nstarting history_setup\n\n")
    history_setup(topology,script_dir)

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