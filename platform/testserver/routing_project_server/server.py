"""A small web-server hosting all mini-internet tools."""

from typing import Optional
from urllib.parse import urlparse

from flask import Flask, redirect, render_template, request, url_for
from flask_basicauth import BasicAuth
from jinja2 import StrictUndefined

from . import bgp_policy_analyzer, matrix, parsers

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
    'krill-url': "http://{hostname}:3080/index.html",
    'BASIC_AUTH_USERNAME': 'admin',
    'BASIC_AUTH_PASSWORD': 'admin',
}

# TODO
app.config['BASIC_AUTH_USERNAME'] = config['BASIC_AUTH_USERNAME']
app.config['BASIC_AUTH_PASSWORD'] = config['BASIC_AUTH_PASSWORD']
basic_auth = BasicAuth(app)


@app.route("/")
def index():
    """Redict to matrix as starting page."""
    return redirect(url_for("matrix"))


@app.route("/krill")
def krill():
    """Allow access to krill, which is embedded as an iframe."""
    hostname = urlparse(request.base_url).hostname
    krill_url = config['krill-url'].format(hostname=hostname)
    return render_template("krill.html", krill_url=krill_url)


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

    # Compute percentages as well.
    valid, invalid, failure = 0, 0, 0
    for src, dsts in connectivity.items():
        for dst, connected in dsts.items():
            if connected:
                # We have connectivity, now check if valid.
                if validity.get(src, {}).get(dst, False):
                    valid += 1
                else:
                    invalid += 1
            else:
                failure += 1
    total = valid + invalid + failure
    valid = round(valid / total * 100)
    invalid = round(invalid / total * 100)
    failure = round(failure / total * 100)

    return render_template(
        'matrix.html',
        connectivity=connectivity, validity=validity,
        valid=valid, invalid=invalid, failure=failure,
    )


@app.route("/bgp-analysis")
@basic_auth.required
def bgp_analysis():
    """Return the full BGP analysis report."""
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

    messages = bgp_policy_analyzer.bgp_report(
        as_data, connection_data, looking_glass_data
    )

    return render_template("bgp_analysis.html", messages=messages,)


@app.route("/looking-glass")
@app.route("/looking-glass/<int:group>")
@app.route("/looking-glass/<int:group>/<router>")
def looking_glass(
        group: Optional[int] = None, router: Optional[str] = None):
    """Show the looking glass for group (AS) and router."""
    looking_glass_files = parsers.find_looking_glass_textfiles(
        config['locations']['groups']
    )
    need_redirect = False

    if (group is None) or (group not in looking_glass_files):
        # Redict to a possible group.
        group = min(looking_glass_files.keys())
        need_redirect = True

    groupdata = looking_glass_files[group]

    if (router is None) or (router not in groupdata):
        # Redirect to first possible router.
        router = next(iter(groupdata))
        need_redirect = True

    if need_redirect:
        return redirect(url_for("looking_glass", group=group, router=router))

    # Now get data for group. First the actual looking glass.
    with open(groupdata[router]) as file:
        filecontent = file.read()

    # Next the analysis.
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
    messages = bgp_policy_analyzer.analyze_bgp(
        group, as_data, connection_data, looking_glass_data
    )

    # Prepare template.
    dropdown_groups = list(looking_glass_files.keys())
    dropdown_routers = list(groupdata.keys())
    return render_template(
        "looking_glass.html",
        filecontent=filecontent,
        bgp_hints=messages,
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
    all_ases = {c[0]["asn"] for c in connections}.union(
        {c[1]["asn"] for c in connections})

    def _check_as(data_a, data_b):
        if ((group is None) or (data_a['asn'] == group)) and \
                ((othergroup is None) or (data_b['asn'] == othergroup)):
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
        dropdown_others={conn[1]['asn'] for conn in selected_connections},
    )


if __name__ == "__main__":
    # Put info other dir.
    import bjoern

    bjoern.run(app, "127.0.0.1", 8000)
