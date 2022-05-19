"""Various file parsers.

TODO: Do not hardcode filenames (e.g. looking glass files)
"""

import csv
import json
import os
import re
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple


def find_looking_glass_textfiles(directory: os.PathLike) \
        -> Dict[int, Dict[str, Path]]:
    """Find all available looking glass files."""
    results = {}
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

    return results


def parse_looking_glass_json(directory: os.PathLike) -> \
        Dict[int, Dict[str, Dict]]:
    """Load looking glass json data.

    Dict structure: AS -> Router -> looking-glass data.
    """
    # Note: group 1 = AS 1; group/as is used interchangeable.
    results = {}
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
    return results


def parse_as_config(filename: os.PathLike,
                    router_config_dir: Optional[os.PathLike] = None) \
        -> Dict[int, Dict]:
    """Return dict of ASes with their type and optionally connected routers.

    The available routers are only loaded if `router_config_dir` is provided.
    """
    reader = csv.reader(_read_clean(filename), delimiter='\t')
    results = {}
    for row in reader:
        asn = int(row[0])
        results[asn] = {'type': row[1]}

        if router_config_dir is not None:
            router_config_file = Path(router_config_dir) / Path(row[3])

            if not router_config_file.is_file():
                continue

            r_reader = csv.reader(_read_clean(
                router_config_file), delimiter='\t')
            results[asn]['routers'] = [row[0] for row in r_reader]

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
    reader = csv.DictReader(
        _read_clean(filename), fieldnames=header, delimiter='\t')

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
    reader = csv.DictReader(
        _read_clean(filename), fieldnames=header, delimiter='\t')

    connections = []
    for row in reader:
        row["a_asn"] = int(row["a_asn"])
        row["b_asn"] = int(row["b_asn"])
        link = {
            'bandwith': int(row['bw']),
            'delay': int(row['delay']),
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


def parse_matrix_connectivity(filename: os.PathLike):
    """Parse the connectivity file provided by the matrix container."""
    results = []
    reader = csv.reader(_read_clean(filename), delimiter='\t')
    for row in reader:
        results.append((int(row[0]), int(row[1]), True if row[2] == 'True' else False))
    return results


def _read_json_safe(filename: os.PathLike, sleep_time=0.01, max_attempts=200):
    """Read a json file, waiting if the file si currently modified."""
    path = Path(filename)
    for current_attempt in range(1, max_attempts+1):
        try:
            with open(path) as file:
                return json.load(file)
        except json.decoder.JSONDecodeError as error:
            if current_attempt == max_attempts:
                # raise error
                print ('WARNING: could not read {} and path validity.'.format(filename))
                print ('We assume empty BGP configuration for this router')
    
                # return the same json as if BGP was not running in the router.
                return {'warning':'Default BGP instance not found'}

            # The file may have changed, wait a bit.
            time.sleep(sleep_time)


def _read_clean(filename: os.PathLike) -> List[str]:
    """Read a file and make sure that all delimiters are single tabs."""
    with open(Path(filename)) as file:
        return [re.sub('\s+', '\t', line) for line in file]
