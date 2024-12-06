"""Various file parsers.

TODO: Do not hardcode filenames (e.g. looking glass files)
"""

import csv
import json
import os
import re
import time
from datetime import datetime, timedelta
import subprocess
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from datetime import datetime as dt
from base64 import b64encode


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
                    groupresults[routerdir.name] =_read_json_safe(looking_glass_file) or {'warning': 'Default BGP instance not found'}
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
                print(f'WARNING: could not read {format(filename)} and path validity. Error message: {error}')
                return None

            # The file may have changed, wait a bit.
            time.sleep(sleep_time)


def _read_clean(filename: os.PathLike) -> List[str]:
    """Read a file and make sure that all delimiters are single tabs."""
    try:
        with open(Path(filename)) as file:
            return [re.sub('\s+', '\t', line) for line in file]
    except:
        print("Error accessing " + filename)
        return []

import os
from pathlib import Path
import subprocess

def parse_qrcode(input_file: os.PathLike, output_file: os.PathLike = None, overwrite=True) -> os.PathLike:
    """Generates or updates the QR code for a given file. Returns None on failure or a Path to the .png file."""
    
    if output_file is None:
        output_file = input_file.with_suffix('.png') 

    if not input_file.is_file():
        print(f"Error: File not found: {input_file.as_posix()}")
        return None

    if output_file.is_file() and not overwrite:
        return output_file

    # Check if qrencode is installed
    try:
        check_version = subprocess.run(
            ["qrencode", "--version"],
            timeout=2,
            capture_output=True,
            text=True,
            check=True
        )
    except subprocess.CalledProcessError as e:
        print(f"Error: qrencode not installed. Stderr:\t{e.stderr}")
        return None

    # Generate the QR code
    try:
        subprocess.run(
            ["qrencode", "-r", input_file.as_posix(), "-o", output_file.as_posix()],
            timeout=2,
            check=True
        )
    except Exception as e:
        print(f"Error when generating the QR code. Stderr:\t{e.stderr}")
        return None

    return output_file


def parse_as_b64(filename: os.PathLike) -> str:
    """Parse a file as base64 ASCII string.
    This can be used to embedd images directly in HTML."""

    if filename == None or not filename.is_file():
        print("Error, file not found: " + filename.as_posix())
        return None

    with open(filename, 'rb') as byte_stream:
        encoded_string = b64encode(byte_stream.read()).decode('utf-8')

    return encoded_string

def parse_wg_conf_ip(filename: os.PathLike) -> str:
    """Parses a wireguard configuration file and extracts the IP address of the interface."""
    if filename is None or not filename.is_file():
        print("Error, file not found: " + filename.as_posix())
        return "No IP address found!"
    
    with open(filename) as file:
        for line in file:
            line = line.strip()
            if line.startswith("Address="):
                return line.split("=", 1)[1]  # Split at the '=' and return the second part
    return "No IP address found!"

def format_bytes(bytes):
    from math import log2, floor

    units = ["B", "KiB", "MiB", "GiB"]
    factor = 1024  # 1 KiB = 1024 bytes
    
    # Determine the unit index (0 for B, 1 for KiB, etc.)
    index = min(floor(log2(bytes) / log2(factor)) if bytes >= 1 else 0, len(units) - 1)
    
    # Convert value to the selected unit
    value = bytes / (factor ** index)
    
    return f"{value:.2f} {units[index]}"

def parse_wg_dump(filename: os.PathLike, interface_name="vpn"):
    """Parses the json  file that the wg-json script dumps."""
    wg_dump = _read_json_safe(filename)
    raw_peers = wg_dump[interface_name]['peers']
    parsed_peers = []

    # Insert missing defaults
    for key, raw_peer in raw_peers.items():
        raw_peer.setdefault('endpoint', None)
        raw_peer.setdefault('latestHandshake', None)
        raw_peer.setdefault('transferRx', 0)
        raw_peer.setdefault('transferTx', 0)
        raw_peers[key] = raw_peer
    
    # Parse data
    for raw_peer in raw_peers.values():
        parsed_peer = {}
        
        #IP Address
        parsed_peer['ip_address'] = raw_peer['allowedIps'][0]

        # Endpoint
        parsed_peer['endpoint'] = raw_peer['endpoint'] or None

        # Last seen string
        if not raw_peer['latestHandshake']:
            parsed_peer['lastSeen'] = "Never"
            parsed_peer['isConnected'] = 0
        else:
            lastSeen = datetime.fromtimestamp(raw_peer['latestHandshake'])
            parsed_peer['lastSeen'] = lastSeen.strftime("%H:%M - %d %B")
            parsed_peer['isConnected'] = int((datetime.now() - lastSeen) < timedelta(seconds=150))

        # RX/TX values
        parsed_peer['transferRxUnits'] = format_bytes(raw_peer['transferRx'])
        parsed_peer['transferTxUnits'] = format_bytes(raw_peer['transferTx'])

        parsed_peers.append(parsed_peer)

    return parsed_peers
