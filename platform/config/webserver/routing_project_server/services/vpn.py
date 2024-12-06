import os
import sqlite3
from typing import Dict
from pathlib import Path
from flask import send_file, current_app
from .parsers import parse_as_config, parse_as_b64, parse_wg_conf_ip, parse_qrcode, parse_wg_dump

def vpn_init(app):
    """Initialize the vpn database."""
    db_path = Path(app.config['LOCATIONS']['vpn_db'])
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Create Interface table
    cursor.execute('''CREATE TABLE IF NOT EXISTS Interfaces (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_id INTEGER NOT NULL,
        config_file TEXT NOT NULL,
        router_name TEXT NOT NULL,
        ip_address TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )''') 

    # Create Peer table
    cursor.execute('''CREATE TABLE IF NOT EXISTS Peers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        interface_id INTEGER NOT NULL,
        peer_name TEXT NOT NULL,
        config_file TEXT NOT NULL,
        in_use INTEGER,
        ip_address TEXT NOT NULL,
        lastSeen TEXT, 
        isConnected INTEGER,
        transferRxUnits TEXT,
        transferTxUnits TEXT,
        endpoint TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(interface_id) REFERENCES Interfaces(id)
    )''')

    conn.commit()
    cursor.execute("SELECT COUNT(*) FROM Interfaces")
    interface_count = cursor.fetchone()[0]
    conn.close()

    if interface_count == 0:
        print(f"No interfaces found in database. Parsing interfaces from config files...")
        vpn_db_populate(app.config['LOCATIONS'])

def vpn_db_populate(locations):
    """Clear the database and repopulate it using the appropriate functions."""
    vpn_db_populate_interfaces(locations)
    vpn_db_populate_peers(locations)

def vpn_db_populate_interfaces(locations):
    """Populate the database Interfaces table by parsing data from the filesystem."""
    db_path = Path(locations['vpn_db'])
    
    # Get a list of all routers
    as_data = parse_as_config(
        locations['as_config'],
        router_config_dir=locations['config_directory'],
    )
    
    # Loop through each router in each group:
    for group_id in as_data.keys():
        try:
            for router in dict.fromkeys(as_data[group_id]['routers']):  # The dict.fromkeys gets rid of duplicates in the router list.
                interface_config_path = (
                    Path(locations['groups']) /
                    f"g{group_id}" /
                    router /
                    locations['vpn_folder'] /
                    "interface.conf"
                )
                if Path.is_file(interface_config_path):
                    interface = { 
                        'group_id': group_id,
                        'config_file': interface_config_path.as_posix(),
                        'router_name': router,
                        'ip_address': parse_wg_conf_ip(interface_config_path)
                    }
                    vpn_db_add_interface(db_path, interface)
                else:
                    print("Error: No wireguard config file found for " + interface_config_path.as_posix())
        except Exception as e:
            # IXPs don't have a VPN interface, so this is defined behaviour.
            if as_data[group_id]['type'] == 'IXP':
                continue
            else:
                print(f"Exception caught: {e}")

def vpn_db_populate_peers(locations):
    """Populate the database Peers table by parsing data from the filesystem."""
    db_path = Path(locations['vpn_db'])

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT id, config_file FROM Interfaces")
    results = cursor.fetchall()
    conn.close()
    
    # Loop through each interface's directory to find the peers that are bound to that interface
    directories = {elem[0]:Path(elem[1]).parent for elem in results}
    for interface_id, interface_path in directories.items():
        if not interface_path.is_dir():
            print(f"Error, directory {interface_path.as_posix()} does not exist: ")
            break
        
        for peer_file in sorted(interface_path.glob('*.peer')):
            peer = {
                'interface_id':interface_id,
                'peer_name':peer_file.stem,
                'config_file':peer_file.as_posix(),
                'in_use':0,
                'ip_address':parse_wg_conf_ip(peer_file)
            }
            vpn_db_add_peer(db_path, peer)

def vpn_db_add_interface(db_path: os.PathLike, interface: Dict):
    """Add a new wireguard interface to the database.
    Interface dict must contain the following fields: group_id, config_file, router_name, ip_address."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute('''INSERT INTO Interfaces 
        (group_id, config_file, router_name, ip_address) 
        VALUES (?, ?, ?, ?)''', 
        (interface['group_id'], interface['config_file'], interface['router_name'], interface['ip_address']))
    conn.commit()
    conn.close()

def vpn_get_interfaces(db_path, group_id):
    """Returns a list of interfaces, each containing a Dict with the entries 'id', 'label' """
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT id, router_name FROM Interfaces WHERE group_id = ?", (group_id,))
    results = cursor.fetchall()
    conn.close()
    return {elem[0]:elem[1] for elem in results}

def vpn_db_add_peer(db_path: os.PathLike, peer: Dict):
    """Add a new peer to the database.
    Peer dict must contain the following fields: 'interface_id', 'peer_name', 'config_file', 'in_use', 'ip_address'."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute('''INSERT INTO Peers 
        (interface_id, peer_name, config_file, in_use, ip_address) 
        VALUES (?, ?, ?, ?, ?)''', 
        (peer['interface_id'], peer['peer_name'], peer['config_file'], peer['in_use'], peer['ip_address']))
    conn.commit()
    conn.close()

def vpn_get_peers(db_path: os.PathLike, interface_id, in_use=1, generate_qrcode=1, max_amount=None):
    """Get a list of all peers for a given wireguard interface."""
    vpn_update_status(current_app.config, interface_id=interface_id)

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Get column names
    cursor.execute(f"PRAGMA table_info(Peers)")
    columns = [column[1] for column in cursor.fetchall()]

    # Get rows
    cursor.execute("SELECT * FROM Peers WHERE interface_id = ? AND in_use = ?", (interface_id,in_use))
    results = cursor.fetchall() if max_amount == None else cursor.fetchmany(max_amount)
    conn.close()

    peers = []
    for row in results:
        # Unzip Peers and create QR Codes
        peer = dict(zip(columns, row))
        qr_image_b64 = None
        if generate_qrcode: 
            qr_image_png = parse_qrcode(Path(peer['config_file']))
            qr_image_b64 = parse_as_b64(qr_image_png)
        peer['qr_image'] = qr_image_b64
        peers.append(peer)
    return peers

def vpn_check_peer_permission(db_path: os.PathLike, peer_id: int, group_id: int) -> bool:
    """Check if there exists a peer with the id that is associated to this group."""

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute('''
        SELECT COUNT(*)
        FROM Peers 
        INNER JOIN Interfaces ON interface_id = Interfaces.id
        WHERE Peers.id = ? AND Interfaces.group_id = ?''', 
        (peer_id, group_id)
    )
    result = cursor.fetchone()
    conn.close()
    return result[0] > 0

def vpn_update_peer(db_path, peer_properties: Dict, peer_id: int = None, peer_ip_address: str = None):
    """Update a peer entry. Peer must at least have the entry 'id'"""

    # Construct command
    sql_query = "UPDATE Peers SET "
    parameters = []

    for key, value in peer_properties.items():
        # Never update the id. If we select the peer according to the ip address, we don't update the ip address
        if key == 'id' or (peer_ip_address and key == 'ip_address'):
            pass

        sql_query += (f"{key} = ?, ")
        parameters.append(value)

    # Remove trailing commas
    sql_query = sql_query.rstrip(", ")

    if peer_id:
        sql_query += "WHERE id = ?"
        parameters.append(peer_id)
    elif peer_ip_address:
        sql_query += "WHERE ip_address = ?"
        parameters.append(peer_ip_address)

    # Execute command
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute(sql_query, parameters)
    conn.commit()
    conn.close()

def vpn_send_conf(db_path: os.PathLike, peer_id: int):
    """Sends a requested peer conf file to the client."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute('''
        SELECT Peers.config_file, Interfaces.router_name, Interfaces.group_id, Peers.peer_name
        FROM Peers 
        INNER JOIN Interfaces ON interface_id = Interfaces.id
        WHERE Peers.id = ?''', 
        (peer_id,)
    )
    result = cursor.fetchone()
    conn.close()
    config_file, router_name, group_id, peer_name = result

    if result is None:
        return "Not found", 404

    download_name = f"Mini-Internet {group_id}-{router_name} {peer_name}.conf"
    return send_file(
        config_file,
        as_attachment=True,
        download_name=download_name
    )

def vpn_update_status(config, interface_id):
    conn = sqlite3.connect(config['LOCATIONS']['vpn_db'])
    cursor = conn.cursor()
    cursor.execute(f"SELECT config_file FROM Interfaces WHERE id = {interface_id}")
    result = cursor.fetchone()
    conn.close()
    
    if not result:
        print(f"Error, config file for interface with id {interface_id} not found!")
        return
    
    config_file = result[0]
    peer_status_list = parse_wg_dump(Path(config_file).with_name("status.json"))
    
    for peer_status in peer_status_list:
        vpn_update_peer(config['LOCATIONS']['vpn_db'], peer_status, peer_ip_address=peer_status['ip_address'])

    return