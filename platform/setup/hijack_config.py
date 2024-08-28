#!/usr/bin/env python3
"""For all stub ASes, hijack the other stub in the same area."""

__author__ = "Alexander Dietmüller"
__email__ = "adietmue@ethz.ch"
__date__ = "2023-03-11"

from pathlib import Path
import subprocess
import argparse

# Update these functions if the assignment changes.


def router_ip(asn, router_id):
    """Router IP within group network."""
    return f"{asn}.{150 + router_id}.0.1"


def measurement_subnets(asn, router_id):
    """Measurement source and destination IP within group network."""
    return (
        f"{asn}.0.198.0/24",  # Matrix server.
        f"{asn}.0.199.0/24",  # Measurement server.
        f"{asn}.{100 + router_id}.0.0/24"
    )


parser = argparse.ArgumentParser()
parser.add_argument("directory", type=Path, default=Path.cwd(), nargs="?")
parser.add_argument("--undo", action="store_true")
parser.add_argument("--dry", action="store_true")


def load_config(current_directory):
    """Load config files to determine IPs in the L3 topology."""
    configdir = Path(current_directory) / "config"
    AS_config_file = configdir / "AS_config.txt"
    hijack_file = configdir / "hijacks.txt"

    hijacks = []
    with open(hijack_file) as file:
        for line in file:
            _args = line.split()
            hijacks.append(dict(
                attacker=int(_args[0]),
                victim=int(_args[1]),
                ases=list(map(int, _args[2].split(","))),
                ixp=int(_args[3]),
                peer_node=_args[4],
                ixp_node=_args[5],
            ))

    router_ips = {}  # loopback ips.
    measurement_nets = {}  # source and destination subnets for pings.
    with open(AS_config_file) as file:
        for line in file:
            # Check which config file the AS is using and load that one.
            asn, _, _, router_config_file, *_ = line.split()
            asn = int(asn)
            router_config_file = configdir / router_config_file
            if not router_config_file.exists():
                continue  # Skip ASes without routers, i.e. IXPs.

            asn_ips = {}
            with open(router_config_file) as router_file:
                for id, rline in enumerate(router_file, 1):
                    router, *_ = rline.split()
                    asn_ips[router] = router_ip(asn, id)

                    if "matrix" in rline.lower():
                        # The destination router for the hijack
                        measurement_nets[asn] = measurement_subnets(asn, id)

            if asn_ips:  # Skip ASes without routers, i.e. IXPs.
                router_ips[asn] = asn_ips

    return hijacks, router_ips, measurement_nets


def hijack(*, attacker, victim, ases, ixp,
           peer_node, ixp_node,
           router_ips, measurement_nets, directory, undo=False, dry=False):
    """Hijack victim prefix via IXP."""
    config = dict(
        router_ips=router_ips, measurement_nets=measurement_nets,
        directory=directory, undo=undo, dry=dry
    )
    # First hijack ASes prefixes towards victim, i.e. at the node which has
    # a session with the victom.
    hijack_via_victim(attacker=attacker, node=peer_node,
                      victim=victim, ases=ases, **config)

    # Next, hijack prefix command via IXP.
    hijack_via_ixp(attacker=attacker, node=ixp_node,
                   victim=victim, ases=ases, ixp=ixp,  **config)


def hijack_via_victim(*, attacker, node, victim, ases,
                      router_ips, measurement_nets, directory,
                      undo=False, dry=False):
    """Attack hijacks AS prefixes towards victim.

    If `undo`, unset the hijack.
    """
    prefixes = [
        prefix for asn in ases for prefix in (
            f"{asn}.0.0.0/8", *measurement_nets[asn],  # source and target.
        )
    ]

    existing_map = f"LOCAL_PREF_OUT_{victim}"
    do_hijack(label="victim", attacker=attacker, node=node, prefixes=prefixes,
              existing_map=existing_map, router_ips=router_ips, directory=directory, min_seq=100, undo=undo, dry=dry)


def hijack_via_ixp(*, attacker, node, victim, ases, ixp,
                   router_ips, measurement_nets, directory,
                   undo=False, dry=False):
    """Attack hijacks victim prefix via IXP."""
    prefixes = [
        f"{victim}.0.0.0/8",
        *measurement_nets[victim],  # source and target.
    ]
    existing_map = f"IXP_OUT_{ixp} "
    communities = " ".join([f"{ixp}:{asn}" for asn in ases])
    community_update = f"set community {communities}"
    do_hijack(label="ixp", attacker=attacker, node=node, prefixes=prefixes,
              existing_map=existing_map, existing_map_update=community_update,
              router_ips=router_ips, directory=directory,
              min_seq=200, undo=undo, dry=dry)


def do_hijack(*, label, attacker, node, prefixes,
              existing_map, existing_map_update="",
              router_ips, directory, min_seq=100, undo=False, dry=False):
    """Execute the hijack."""
    label = str(label).upper()
    no = "no " if undo else ""
    # First get all static routes, otherwise we can't advertise the prefixes.
    static_routes = "\n".join([f"{no}ip route {prefix} Null0"
                               for prefix in prefixes])
    # Next prepare prefix lists for matching
    prefix_list_name = f"HIJACKED_PREFIX_{label}"
    prefix_list = "\n".join([
        f"{no}ip prefix-list {prefix_list_name} seq {min_seq + n} "
        f"permit {prefix}" for n, prefix in enumerate(prefixes)
    ])
    # Finally, we need to advertise the prefixes as well.
    announcements = "\n".join([f"{no}network {prefix}" for prefix in prefixes])

    # Do not send the hijacked prefix via iBGP by adding a route-map.
    no_hijack_name = f"NO_HIJACK_{label}"
    ibgp_neighbors = [
        ip for router, ip in router_ips[attacker].items()
        if node not in router
    ]
    ibgp_routemap_assignment = "\n".join([
        f"{no}neighbor {neighbor} route-map {no_hijack_name} out"
        for neighbor in ibgp_neighbors
    ])

    # Create command file that can be executed on the router.
    commands = f"""
#!/usr/bin/vtysh -f
# Ensure we can advertise the prefixes.
{static_routes}
# Configure prefix list for route-maps.
{prefix_list}
# Set up up route-maps.
# First update the existing one.
route-map {existing_map} permit {min_seq}
{no}match ip address prefix-list {prefix_list_name}
{no + existing_map_update if existing_map_update else ""}
exit
{f"no route-map {existing_map} permit {min_seq}" if undo else ""}
# Second create the new map to prevent advertisting the hijack over iBGP.
route-map {no_hijack_name} deny {min_seq}
{no}match ip address prefix-list {prefix_list_name}
exit
{f"no route-map {no_hijack_name} deny {min_seq}" if undo else ""}
# as part of that, let everything not blocked through.
route-map {no_hijack_name} permit {min_seq + 1}
exit
{f"no route-map {no_hijack_name} permit {min_seq + 1}" if undo else ""}
# Finally, announce hijacks and install route maps.
router bgp {attacker}
address-family ipv4 unicast
{announcements}
{ibgp_routemap_assignment}
exit
""".strip()

    # Run or print command.
    docker_cp_exec(label=label, group=attacker, node=node, commands=commands,
                   directory=directory, dry=dry)


def docker_cp_exec(*, label, group, node, commands, directory, dry=False):
    """Run command in container.

    First create the file, copy it to the container, then execute.
    Copying is done for compatibility with the other config scripts.
    """
    container = f"{group}_{node}router"
    if dry:
        print("=====================================================")
        print(f"Config for {container} ({label.lower()}):")
        print("=====================================================")
        print(commands)
        return

    config_file = Path(directory) / f"groups/g{group}/{node}/config/"\
        "conf_hijack.sh"
    with open(config_file, "w") as file:
        file.write(commands)
    make_executable(config_file)

    # Copy to container.
    container_file = "/home/conf_hijack.sh"
    subprocess.run(
        f"docker cp {config_file} {container}:{container_file} > /dev/null",
        shell=True, check=True,
    )
    subprocess.run(f"docker exec {container} .{container_file}",
                   shell=True, check=True)


def make_executable(path):
    """Equivalent to chmod +x.

    Adapted to use pathlib from https://stackoverflow.com/a/30463972
    """
    mode = path.stat().st_mode
    mode |= (mode & 0o444) >> 2    # copy R bits to X
    path.chmod(mode)


if __name__ == "__main__":
    parsed = parser.parse_args()
    _dir = parsed.directory
    undo = parsed.undo
    dry = parsed.dry

    _hijacks, _router_ips, _measurement_nets = load_config(_dir)
    config = dict(
        router_ips=_router_ips, measurement_nets=_measurement_nets,
        directory=_dir, undo=undo, dry=dry,
    )

    for current, hijacks_spec in enumerate(_hijacks, 1):
        if not dry:
            print(f"Hijack {current}/{len(_hijacks)}:",
                f"AS {hijacks_spec['attacker']} hijacks",
                f"AS {hijacks_spec['victim']}.",
                end="\r")
        hijack(**hijacks_spec, **config)
    if not dry:
        # Add enough space to overwrite the last line.
        print(f"{len(_hijacks)} hijacks complete.                          ")
