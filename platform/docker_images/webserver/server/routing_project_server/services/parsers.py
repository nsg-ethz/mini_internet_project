"""Various file parsers.

TODO: Do not hardcode filenames (e.g. looking glass files)
"""

import csv
import json
import os
import re
import time
import subprocess
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from datetime import datetime as dt


def find_looking_glass_textfiles(directory: os.PathLike) \
        -> Dict[int, Dict[str, Path]]:
    """Find all available looking glass files."""
    results = {}
    try:
        for groupdir in Path(directory).iterdir():
            if not groupdir.is_dir() or not groupdir.name.startswith('g'):
                # Groups have directories gX with X being the group number.
                # Ignore other dirs.
                continue
            group = int(groupdir.name.replace('g', ''))
            groupresults = {}
            for routerdir in groupdir.iterdir():
                if not routerdir.is_dir():
                    continue
                # Check if there is a looking_glass file.
                looking_glass_file = routerdir / "looking_glass.txt"
                if looking_glass_file.is_file():
                    groupresults[routerdir.name] = looking_glass_file
            if groupresults:
                results[group] = groupresults
    except:
        print("Error when accessing " + directory)

    return results


def parse_looking_glass_json(directory: os.PathLike) -> \
        Dict[int, Dict[str, Dict]]:
    """Load looking glass json data.

    Dict structure: AS -> Router -> looking-glass data.
    """
    # Note: group 1 = AS 1; group/as is used interchangeable.
    results = {}
    try:
        for groupdir in Path(directory).iterdir():
            if not groupdir.is_dir() or not groupdir.name.startswith('g'):
                # Groups have directories gX with X being the group number.
                # Ignore other dirs.
                continue
            group = int(groupdir.name.replace('g', ''))
            groupresults = {}
            for routerdir in groupdir.iterdir():
                if not routerdir.is_dir():
                    continue
                # Check if there is a looking_glass file.
                looking_glass_file = routerdir / "looking_glass_json.txt"
                if looking_glass_file.is_file():
                    groupresults[routerdir.name] = _read_json_safe(
                        looking_glass_file)
            if groupresults:
                results[group] = groupresults
    except:
        print("Error when accessing " + directory)
    return results


def parse_as_config(filename: os.PathLike,
                    router_config_dir: Optional[os.PathLike] = None) \
        -> Dict[int, Dict]:
    """Return dict of ASes with their type and optionally connected routers.

    The available routers are only loaded if `router_config_dir` is provided.
    """

    results = {}
    try:
        reader = csv.reader(_read_clean(filename), delimiter='\t')
        for row in reader:
            asn = int(row[0])
            results[asn] = {'type': row[1]}

            if row[2] == "Config":
                results[asn]["all_in_one"] = True
            else:
                results[asn]["all_in_one"] = False

            if router_config_dir is not None:
                router_config_file = Path(router_config_dir) / Path(row[3])

                if not router_config_file.is_file():
                    continue

                r_reader = csv.reader(_read_clean(
                    router_config_file), delimiter='\t')
                results[asn]['routers'] = [row[0] for row in r_reader]
    except:
        print("Failed to read " + filename)

    return results


def parse_public_as_connections(filename: os.PathLike) \
        -> List[Tuple[Dict, Dict]]:
    """Parse the (public) file with inter-as config.

    This parses the "public" file which contains assigned IP addresses;
    i.e. the file intended for students.

    Each tuple contains one dict per entity in the connection with AS number,
    router, and role (provider, customer, peer) as well as the IP address
    for the interface.
    """
    header = [
        'a_asn', 'a_router', 'a_role',
        'b_asn', 'b_router', 'b_role',
        'a_ip',
    ]
    try:
        reader = csv.DictReader(
            _read_clean(filename), fieldnames=header, delimiter='\t')
    except:
        print("Failed to read: " + filename)
        return None

    data = {}
    for row in reader:
        row["a_asn"] = int(row["a_asn"])
        row["b_asn"] = int(row["b_asn"])

        a = tuple(row[f"a_{key}"] for key in ["asn", "router", "role"])
        b = tuple(row[f"b_{key}"] for key in ["asn", "router", "role"])

        if (a, b) in data:
            raise RuntimeError("Duplicate connection!")
        elif (b, a) in data:
            # Connection is already in database, just add
            # IP Address for the other side.
            data[(b, a)][1]['ip'] = row['a_ip']
        else:
            # Add new connection
            data[(a, b)] = tuple(
                {key: row[f"{side}_{key}"]
                    for key in ["asn", "router", "role"]}
                for side in ("a", "b")
            )
            data[(a, b)][0]['ip'] = row['a_ip']
            data[(a, b)][1]['ip'] = None

    # Sort by AS.
    connections = sorted(data.values(),
                         key=lambda x: (x[0]['asn'], x[1]['asn']))
    return connections


def parse_as_connections(filename: os.PathLike) \
        -> List[Tuple[Dict, Dict]]:
    """Parse the full config file with inter-as configs.

    Each tuple contains one dict per entity in the connection with AS number,
    router, and role (provider, customer, peer) as well as the link information
    (bandwidth, delay, and subnet).
    """
    header = [
        'a_asn', 'a_router', 'a_role',
        'b_asn', 'b_router', 'b_role',
        'bw', 'delay', 'subnet',
    ]
    try:
        reader = csv.DictReader(
            _read_clean(filename), fieldnames=header, delimiter='\t')

        connections = []
        for row in reader:
            row["a_asn"] = int(row["a_asn"])
            row["b_asn"] = int(row["b_asn"])
            link = {
                'bandwith': row['bw'],
                'delay': row['delay'],
                'subnet': row['subnet'],
            }

            connection = tuple(
                {key: row[f"{side}_{key}"] for key in ["asn", "router", "role"]}
                for side in ('a', 'b')
            )
            # Now replace N/As with None and add link data to both sides.
            for sidedata in connection:
                if sidedata['router'] == 'N/A':
                    sidedata['router'] = None
                sidedata.update(link)
            connections.append(connection)

        return sorted(connections, key=lambda x: (x[0]['asn'], x[1]['asn']))
    except:
        return []


def parse_matrix_connectivity(filename: os.PathLike):
    """Parse the connectivity file provided by the matrix container."""
    results = []
    reader = csv.reader(_read_clean(filename), delimiter='\t')
    for row in reader:
        results.append((int(row[0]), int(row[1]),
                       True if row[2] == 'True' else False))
    return results


def parse_matrix_stats(filename: os.PathLike):
    """Read the matrix stats file."""
    try:
        with open(filename) as file:
            stats = json.load(file)
    except (FileNotFoundError, json.decoder.JSONDecodeError):
        return None, None

    return (
        dt.fromisoformat(stats['current_time']),
        stats['update_frequency'],
    )


def _read_json_safe(filename: os.PathLike, sleep_time=0.01, max_attempts=200):
    """Read a json file, waiting if the file is currently modified."""
    path = Path(filename)
    for current_attempt in range(1, max_attempts+1):
        try:
            with open(path) as file:
                return json.load(file)
        except json.decoder.JSONDecodeError as error:
            if current_attempt == max_attempts:
                # raise error
                print('WARNING: could not read {} and path validity.'.format(filename))
                print('We assume empty BGP configuration for this router')

                # return the same json as if BGP was not running in the router.
                return {'warning': 'Default BGP instance not found'}

            # The file may have changed, wait a bit.
            time.sleep(sleep_time)
            return None
    return None


def _read_clean(filename: os.PathLike) -> List[str]:
    """Read a file and make sure that all delimiters are single tabs."""
    try:
        with open(Path(filename)) as file:
            return [re.sub('\s+', '\t', line) for line in file]
    except:
        print("Error accessing " + filename)
        return []


def parse_topology_txt(config_defaults):
    topology_txt = config_defaults['LOCATIONS'].get('topology_txt')
    topology_json = config_defaults['LOCATIONS'].get('topology_json')

    nodes = []
    edges = []
    seen_nodes = set()

    def extract_node_number(as_name):
        return int(re.findall(r"\d+", as_name)[0])

    def strip_pt(value):
        return float(value.replace("pt", ""))

    def scale_coordinates(node_data, scale_f):
        for node in node_data:
            node['x'] *= scale_f
            node['y'] *= scale_f
        return node_data

    # Parse input file
    if not os.path.exists(topology_txt):
        print(f"[ERROR] topology.txt not found at {topology_txt}")
        return
    else:
        with open(topology_txt, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()

                if line.startswith("node"):
                    match = re.match(r"node (\S+) (\S+) (-?\d+\.?\d*)pt (-?\d+\.?\d*)pt", line)
                    if match:
                        node_id, role, x_str, y_str = match.groups()
                        node_num = extract_node_number(node_id)

                        if node_num not in seen_nodes:
                            seen_nodes.add(node_num)
                            nodes.append({
                                "id": node_num,
                                "label": str(node_num),
                                "type": role.lower(),
                                "x": strip_pt(x_str),
                                "y": -strip_pt(y_str),
                                "fixed": True
                            })

                elif line.startswith("edge"):
                    match = re.match(r"edge (\S+) (\S+) (\S+)", line)
                    if match:
                        from_id = extract_node_number(match.group(1))
                        to_id = extract_node_number(match.group(2))
                        edge_type = match.group(3).lower()
                        edges.append({
                            "from": from_id,
                            "to": to_id,
                            "type": edge_type
                        })

    # Scale coordinates
    scale_factor = 1.5
    nodes = scale_coordinates(nodes, scale_factor)

    # Prepare data object
    data = {"nodes": nodes, "edges": edges}

    # Check if content changed (optional optimization)
    if os.path.exists(topology_json):
        with open(topology_json, "r", encoding="utf-8") as f:
            existing = json.load(f)
        if existing == data:
            return  # No need to rewrite

    # Write to output
    with open(topology_json, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)

    print(f"Updated topology JSON: {topology_json}")


def call_subnet_func(func_name: str, args: List[str], script_path: os.PathLike) -> str:
    args_str = " ".join(map(str, args))
    cmd = f"source '{script_path}'; {func_name} {args_str}"
    return subprocess.check_output(["bash", "-c", cmd], text=True).strip()


def get_router_interfaces_from_config(router_name: str, group_number: int, directory: os.PathLike) -> Dict[str, any]:
    router_info = {
        "name": router_name,
        "group_number": group_number,
        "interfaces": [],
        "is_border": False
    }

    # === External links (from aslevel_links_students.txt) ===
    public_as_connections = directory / "aslevel_links_students.txt"
    external_links = parse_public_as_connections(public_as_connections)
    script_path = directory / "subnet_config.sh"

    for a, b in external_links:
        for side, dev in [(a, "1"), (b, "2")]:
            if int(side["asn"]) == group_number and side["router"] == router_name:
                # External interface found
                router_info["interfaces"].append({
                    "ip": side.get("ip").split("/")[0],
                    "type": "external"
                })
                router_info["is_border"] = True

    # === Internal links (file referenced in AS_config.txt) ===
    as_conf_path = directory / "AS_config.txt"
    internal_link_file = None

    # Determine the filename containing internal links for this AS
    with open(as_conf_path) as f:
        for line in f:
            parts = line.strip().split()
            if parts and parts[0] == str(group_number):
                if len(parts) >= 5:
                    internal_link_file = directory / parts[4]
                break

    # If file exists, parse links and generate IPs via Bash function
    if internal_link_file and internal_link_file.exists():
        with open(internal_link_file) as f:
            links = [line.strip().split() for line in f if line.strip()]
            for idx, (r1, r2, *_rest) in enumerate(links):
                if router_name == r1:
                    ip = call_subnet_func("subnet_router_router_intern", [group_number, idx, "1"], script_path)
                    router_info["interfaces"].append({
                        "ip": ip.split("/")[0],
                        "type": "internal"
                    })
                elif router_name == r2:
                    ip = call_subnet_func("subnet_router_router_intern", [group_number, idx, "2"], script_path)
                    router_info["interfaces"].append({
                        "ip": ip.split("/")[0],
                        "type": "internal"
                    })

    return router_info


def get_all_routers(config_dir: os.PathLike) -> Dict[int, Dict]:
    config_dir = Path(config_dir)
    public_as_connections = config_dir / "aslevel_links_students.txt"
    as_config_file = config_dir / "AS_config.txt"
    script_path = config_dir / "subnet_config.sh"

    # Parse public AS connections
    connections = parse_public_as_connections(public_as_connections)

    # Initialize public_links per AS
    public_links_map = {}

    # Go through each connection and prepare public link entries
    for a, b in connections:
        ip_a = a.get("ip", "").split("/")[0] if a.get("ip") else None
        ip_b = b.get("ip", "").split("/")[0] if b.get("ip") else None
        subnet = None
        if ip_a:
            subnet = f"{ip_a.rsplit('.', 1)[0]}.0/24"

        for side, peer in [(a, b), (b, a)]:
            asn = int(side["asn"])
            if asn not in public_links_map:
                public_links_map[asn] = []

            public_links_map[asn].append({
                "peer_asn": int(peer["asn"]),
                "router": side["router"],
                "peer_router": peer["router"],
                "ip": side.get("ip", "").split("/")[0] if side.get("ip") else None,
                "peer_ip": peer.get("ip", "").split("/")[0] if peer.get("ip") else None,
                "role": side["role"],
                "peer_role": peer["role"],
                "subnet": subnet
            })

    # Load AS config and prepare full result
    as_info = parse_as_config(as_config_file, config_dir)
    result = {}

    for asn, info in as_info.items():
        if info.get("type") != "AS":
            continue  # Skip non-AS entries

        seen = set()
        routers_list = []
        for r in info.get("routers", []):
            if r not in seen:
                seen.add(r)
                routers_list.append(r)
        router_map = {}

        for idx, router_name in enumerate(routers_list):
            try:
                loopback_ip = call_subnet_func("subnet_router", [asn, idx, "router"], script_path)
                loopback_ip = loopback_ip.split("/")[0]

                host_ip = call_subnet_func("subnet_host_router", [asn, idx, "host"], script_path)
                host_ip = host_ip.split("/")[0]
                host_name = derive_container_name(asn, router_name, "host", info.get("all_in_one"))
            except subprocess.CalledProcessError as e:
                print(f"Error getting IP for AS{asn} router {router_name}: {e}")
                continue

            router_details = get_router_interfaces_from_config(router_name, asn, config_dir)
            container_name = derive_container_name(asn, router_name, "router")

            interfaces = router_details["interfaces"]
            interfaces.insert(0, {
                "ip": loopback_ip,
                "type": "loopback"
            })

            router_map[router_name] = {
                "is_border": router_details["is_border"],
                "interfaces": interfaces,
                "container": container_name,
                "host": {
                    "container": host_name,  # Adjust to your actual naming convention
                    "ip": host_ip
                }
            }

        result[asn] = {
            "type": info["type"],
            "routers": router_map,
            "public_links": public_links_map.get(asn, [])
        }

    return result


def derive_container_name(asn: int, name: str, container_type: str, all_in_one: bool = False) -> Optional[str]:
    """Derive Docker container name."""
    if container_type == "router":
        return f"{asn}_{name}router"
    elif container_type == "host":
        if not all_in_one:
            return f"{asn}_{name}host"
        else:
            return f"{asn}_{name}host0"
    return None
