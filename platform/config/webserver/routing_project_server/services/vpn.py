import os
import sqlite3
from typing import List, Tuple, Dict
from pathlib import Path
from flask import current_app, url_for, send_file, redirect
from .parsers import parse_as_config, parse_as_b64, parse_wg_conf_ip, parse_qrcode

def db_flush_table(db_path, table_name):
    """Flush a table of the database. Does not reset the primary id increment counter."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute(f"DELETE FROM {table_name}")
    conn.commit()
    conn.close()

def vpn_db_init(app_config):
    """Initialize the vpn database."""
    db_path = Path(app_config['LOCATIONS']['vpn_db'])
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Create Interface table
    cursor.execute('''CREATE TABLE IF NOT EXISTS Interfaces (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_id INTEGER NOT NULL,
        config_file TEXT NOT NULL,
        router_name TEXT NOT NULL,
        ip_address TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        last_used TIMESTAMP
    )''') 

    # Create Peer table
    cursor.execute('''CREATE TABLE IF NOT EXISTS Peers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        interface_id INTEGER NOT NULL,
        peer_name TEXT NOT NULL,
        config_file TEXT NOT NULL,
        in_use INTEGER,
        ip_address TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        last_used TIMESTAMP,
        FOREIGN KEY(interface_id) REFERENCES Interfaces(id)
    )''')

    conn.commit()
    conn.close()

def vpn_db_populate(app_config):
    """Clear the database and repopulate it using the appropriate functions."""
    db_path = Path(app_config['LOCATIONS']['vpn_db'])

    # Delete old entries to avoid duplicates
    # TODO: Update instead of delete
    # cursor.execute("DROP TABLE IF EXISTS Interfaces")
    db_flush_table(db_path, "Interfaces")
    # cursor.execute("DROP TABLE IF EXISTS Peers")
    db_flush_table(db_path, "Peers")

    vpn_db_populate_interfaces(app_config)
    vpn_db_populate_peers(app_config)

def vpn_db_populate_interfaces(app_config):
    """Populate the database Interfaces table by parsing data from the filesystem."""
    db_path = Path(app_config['LOCATIONS']['vpn_db'])
    
    # Get a list of all routers
    as_data = parse_as_config(
        app_config['LOCATIONS']['as_config'],
        router_config_dir=app_config['LOCATIONS']['config_directory'],
    )
    
    # Loop through each router in each group:
    for group_id in as_data.keys():
        try:
            for router in dict.fromkeys(as_data[group_id]['routers']):  # The dict.fromkeys gets rid of duplicates in the router list.
                interface_config_path = (
                    Path(app_config['LOCATIONS']['groups']) /
                    f"g{group_id}" /
                    router /
                    app_config['LOCATIONS']['vpn_folder'] /
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

def vpn_db_populate_peers(app_config):
    """Populate the database Peers table by parsing data from the filesystem."""
    db_path = Path(app_config['LOCATIONS']['vpn_db'])

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


def vpn_get_peers(db_path: os.PathLike, interface_id, in_use=1, generate_qrcode=1):
    """Get a list of all peers for a given wireguard interface
        Return object structure: List with {'id', 'name', 'description', 'qr_image', 'path'}
    """
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT id, peer_name, ip_address, config_file FROM Peers WHERE interface_id = ? AND in_use = ?", (interface_id,in_use))
    results = cursor.fetchall()
    conn.close()

    peers = []
    for peer in results:
        qr_image_b64 = None
        if generate_qrcode: 
            qr_image_png = parse_qrcode(Path(peer[3]))
            qr_image_b64 = parse_as_b64(qr_image_png)
        
        peers.append({
            'id':peer[0],
            'peer_name':peer[1], 
            'ip_address':peer[2], 
            'in_use':  in_use,
            'qr_image':  qr_image_b64,
        })
    return peers

def vpn_update_peer(db_path: os.PathLike, peer):
    """Update 'peer_name' and 'in_use' for a given peer."""

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute('''
        UPDATE Peers
        SET peer_name = ?, in_use = ?
        WHERE id = ?
    ''',
    (peer['peer_name'], peer['in_use'], peer['id']))
    conn.commit()
    conn.close()


def vpn_send_conf(db_path: os.PathLike, peer_id: int, group_id: int):
    """Sends a requested peer conf file to the client.
    We check the group_id to prehibit sql injection. If a user is logged in, she can only access her own peers."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute('''
        SELECT Peers.config_file, Interfaces.router_name
        FROM Peers 
        INNER JOIN Interfaces ON interface_id = Interfaces.id
        WHERE Peers.id = ? AND Interfaces.group_id = ?''', 
        (peer_id, group_id)
    )
    result = cursor.fetchone()
    conn.close()
    config_file, router_name = result

    if result is None:
        return "Not found", 404

    download_name = f"Mini-Internet Group {group_id} {router_name}.conf"
    return send_file(
        config_file,
        as_attachment=True,
        download_name=download_name
    )
