"""A small web-server hosting all mini-internet tools."""

import csv
from ctypes import addressof
from pathlib import Path
from sqlite3 import connect
from typing import Dict, List, Optional, Tuple

from flask import Flask, redirect, render_template, url_for
from jinja2 import StrictUndefined

# from .matrix import make_matrix
from . import parsers, matrix

app = Flask(__name__)
app.jinja_env.undefined = StrictUndefined

# TODO: Put in file
config = {
    'locations': {
        'groups': '/home/alex/routing_project/github/platform/groups',
        'as_config': "/home/alex/routing_project/github/platform/config/AS_config.txt",
        "as_connections_public":
        "/home/alex/routing_project/github/platform/config/external_links_config_students.txt",
        "as_connections":
        "/home/alex/routing_project/github/platform/config/external_links_config.txt",
        "config_directory":
        "/home/alex/routing_project/github/platform/config",
        "matrix": "/home/alex/routing_project/github/platform/groups/matrix/connectivity.txt"
    },
}


@app.route("/matrix")
def connectivity_matrix():
    """Create the connectivity matrix."""
    # Load all required files.
    as_data = parsers.parse_as_config(
        config['locations']['as_config'],
        router_config_dir=config['locations']['config_directory'],
    )
    connection_data = parsers.parse_as_connections(
        config['locations']['as_connections']
    )
    looking_glass_data = parsers.parse_looking_glass_json(
        config['locations']['groups']
    )
    connectivity_data = parsers.parse_matrix_connectivity(
        config['locations']['matrix']
    )

    # Compute results
    connectivity = matrix.check_connectivity(
        as_data, connectivity_data)
    validity = matrix.check_validity(
        as_data, connection_data, looking_glass_data)

    return render_template(
        'matrix.html',
        connectivity=connectivity,
        validity=validity,
    )


@app.route("/looking-glass")
@app.route("/looking-glass/<int:group>")
@app.route("/looking-glass/<int:group>/<router>")
def looking_glass(
        group: Optional[int] = None, router: Optional[str] = None):
    """Show the looking glass for group (AS) and router."""
    looking_glass_data = parsers.find_looking_glass_textfiles(
        config['locations']['groups']
    )
    need_redirect = False

    if (group is None) or (group not in looking_glass_data):
        # Redict to a possible group.
        group = min(looking_glass_data.keys())
        need_redirect = True

    groupdata = looking_glass_data[group]

    if (router is None) or (router not in groupdata):
        # Redirect to first possible router.
        router = next(iter(groupdata))
        need_redirect = True

    if need_redirect:
        return redirect(url_for("looking_glass", group=group, router=router))

    with open(groupdata[router]) as file:
        filecontent = file.read()

    dropdown_groups = list(looking_glass_data.keys())
    dropdown_routers = list(groupdata.keys())

    return render_template(
        "looking_glass.html",
        filecontent=filecontent,
        group=group, router=router,
        dropdown_groups=dropdown_groups, dropdown_routers=dropdown_routers
    )


@app.route("/as-connections")
@app.route("/as-connections/<int:group>")
@app.route("/as-connections/<int:group>/<int:othergroup>")
def as_connections(group: int = None, othergroup: int = None):
    """Show the AS connections, optionally for selected groups only."""
    connections = parsers.parse_public_as_connections(
        config['locations']['as_connections_public'])
    all_ases = {c[0]["as"] for c in connections}.union(
        {c[1]["as"] for c in connections})

    def _check_as(data_a, data_b):
        if ((group is None) or (data_a['as'] == group)) and \
                ((othergroup is None) or (data_b['as'] == othergroup)):
            return True
        return False

    selected_connections = []
    for _a, _b in connections:
        if _check_as(_a, _b):
            selected_connections.append((_a, _b))
        elif _check_as(_b, _a):
            selected_connections.append((_b, _a))

    return render_template(
        "as_connections.html",
        connections=selected_connections,
        group=group,
        othergroup=othergroup,
        # All ASes
        dropdown_groups=all_ases,
        # Only matching ASes for first one.
        dropdown_others={conn[1]['as'] for conn in selected_connections},
    )


def test():
    connectivity_matrix()


if __name__ == "__main__":
    # Put info other dir.
    import bjoern

    bjoern.run(app, "127.0.0.1", 8000)
