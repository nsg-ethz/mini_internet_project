from typing import List, Tuple, Dict
from pathlib import Path
from flask import current_app
from .parsers import parse_as_config

# TODO: dont use hardcoded paths for wireguard config folder and interface files, replace current_app.config instead.
def find_all_ifs(group_number: int) -> Dict:
    """Find all wireguard interfaces for a group.
       Return dict: Router Name -> wireguard folder path"""

    # Get a list of all routers
    as_data = parse_as_config(
        current_app.config['LOCATIONS']['as_config'],
        router_config_dir=current_app.config['LOCATIONS']['config_directory'],
    )
    routers = []
    interfaces = {}

    # All routers of this specific group
    if group_number in as_data.keys():
        routers = as_data[group_number]['routers']
    else:
        print("Error: No As data found for group " + str(group_number))
    
    # Loop through each router in our group and find wireguard interface config files
    group_path = Path(current_app.config['LOCATIONS']['groups'] + '/g' + str(group_number))
    for router in routers:
        interface_folder_path = Path.joinpath(group_path, str(router + "/wireguard"))
        interface_config_path = Path.joinpath(interface_folder_path, "interface.conf")
        if Path.is_file(interface_config_path):
            interfaces[router] = interface_folder_path.as_posix()
        else:
            print("Error: No wireguard config file found for " + interface_config_path.as_posix())

    return interfaces

def get_if_status(group_numer: int) -> List[Tuple[str, Dict]]:
    """Get the status off all wireguard interfaces for a group.
    
        Return object structure: Router name -> Interface property name -> Interface property
    """



    return None