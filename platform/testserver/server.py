"""A small web-server hosting all mini-internet tools."""

import csv
from ctypes import addressof
from pathlib import Path
from sqlite3 import connect
from typing import Dict, List, Optional, Tuple

from flask import Flask, redirect, render_template, url_for
from jinja2 import StrictUndefined

app = Flask(__name__)
app.jinja_env.undefined = StrictUndefined

# TODO: Put in file
config = {
    'looking_glass': {
        'directory': '/home/alex/routing_project/github/platform/groups',
    },
    'as_connections': {
        'filename': '/home/alex/routing_project/github/platform/config/external_links_config_students.txt',
    }
}


@app.route("/")
def hello_world():
    """Say hi!"""
    return "Hello, World!"


@app.route("/looking-glass")
@app.route("/looking-glass/<int:group>")
@app.route("/looking-glass/<int:group>/<router>")
def looking_glass(
        group: Optional[int] = None, router: Optional[str] = None):
    """Show the looking glass for group (AS) and router."""
    looking_glass_data = find_looking_glass_files()
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
    connections = parse_as_connections()
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


def find_looking_glass_files() -> Dict[int, Dict[str, Path]]:
    """Find all available looking glass files."""
    results = {}
    base = Path(config['looking_glass']['directory'])

    for groupdir in base.iterdir():
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


def parse_as_connections() -> List[Tuple[Dict, Dict]]:
    """Parse the file with inter-as config."""
    path = Path(config['as_connections']['filename'])

    connections = []

    header = [
        'a_as', 'a_router', 'a_role',
        'b_as', 'b_router', 'b_role',
        'a_ip',
    ]

    with open(path) as csvfile:
        dialect = csv.Sniffer().sniff(csvfile.read(1024))
        csvfile.seek(0)
        reader = csv.DictReader(
            csvfile, fieldnames=header, dialect=dialect)

        data = {}
        for row in reader:
            row["a_as"] = int(row["a_as"])
            row["b_as"] = int(row["b_as"])

            a = tuple(row[f"a_{key}"] for key in ["as", "router", "role"])
            b = tuple(row[f"b_{key}"] for key in ["as", "router", "role"])

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
                     for key in ["as", "router", "role"]}
                    for side in ("a", "b")
                )
                data[(a, b)][0]['ip'] = row['a_ip']
                data[(a, b)][1]['ip'] = None

        # Sort by AS.
        connections = sorted(data.values(),
                             key=lambda x: (x[0]['as'], x[1]['as']))
        return connections


if __name__ == "__main__":
    import bjoern

    bjoern.run(app, "127.0.0.1", 8000)
