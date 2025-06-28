import math
import json
from typing import Optional
from flask import Blueprint, current_app, jsonify, request
from flask import redirect, render_template, url_for
from urllib.parse import urlparse

from flask_login import login_required, login_user, current_user
from .services.login import LoginForm, User, check_user_pwd, get_current_users_group
from .services import parsers
from .services.bgp_policy_analyzer import prepare_bgp_analysis
from .services.matrix import prepare_matrix
from .services.vpn import find_all_ifs
from .app import basic_auth

main_bp = Blueprint('main', __name__)

@main_bp.route("/")
def index():
    """Redict to matrix as starting page."""
    return redirect(url_for("main.connectivity_matrix"))

@main_bp.route("/matrix")
def connectivity_matrix():
    """Create the connectivity matrix."""
    # Prepare matrix data (or load if using background workers).
    updated, frequency, connectivity, validity = prepare_matrix(current_app.config)

    if 'raw' in request.args:
        # Only send json data
        return jsonify(
            last_updated=updated, update_frequency=frequency,
            connectivity=connectivity, validity=validity,
        )

    # Compute percentages as well.
    valid, invalid, failure = 0, 0, 0
    for src, dsts in connectivity.items():
        for dst, connected in dsts.items():
            if connected:
                # We have connectivity, now check if valid.
                # If validity could not be checked, assume valid.
                if validity.get(src, {}).get(dst, True):
                    valid += 1
                else:
                    invalid += 1
            else:
                failure += 1
    total = valid + invalid + failure
    if total:
        invalid = math.ceil(invalid / total * 100)
        failure = math.ceil(failure / total * 100)
        valid = 100 - invalid - failure

    return render_template(
        'matrix.html',
        connectivity=connectivity, validity=validity,
        valid=valid, invalid=invalid, failure=failure,
        last_updated=updated, update_frequency=frequency,
    )

@main_bp.route("/traceroutes")
def show_topology():
    group_router_map = parsers.get_all_routers(current_app.config['LOCATIONS']['config_directory'])

    if not group_router_map:
        return render_template(
            "topology.html",
            group=None,
            router=None,
            dropdown_groups=[],
            all_routers={}
        )

    group = min(group_router_map)
    router = next(iter(group_router_map[group]["routers"]))

    return render_template(
        "topology.html",
        group=group,
        router=router,
        dropdown_groups=sorted(group_router_map),
        all_routers=group_router_map
    )

@main_bp.route("/traceroutes/routers")
def show_topology_json():
    group_router_map = parsers.get_all_routers(current_app.config['LOCATIONS']['config_directory'])
    return jsonify(group_router_map)
@main_bp.route("/looking-glass")
@main_bp.route("/looking-glass/<int:group>")
@main_bp.route("/looking-glass/<int:group>/<router>")
def looking_glass(
        group: Optional[int] = None, router: Optional[str] = None):
    """Show the looking glass for group (AS) and router."""
    looking_glass_files = parsers.find_looking_glass_textfiles(
        current_app.config['LOCATIONS']['groups']
    )

    if looking_glass_files == {}:
        return render_template(
            "looking_glass.html",
            filecontent="There are no ASes configured!",
            bgp_hints=[],
            group=None, router=None,
            dropdown_groups=[], dropdown_routers=[],
            last_updated=0, update_frequency=0,
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
        return redirect(
            url_for("main.looking_glass", group=group, router=router))

    # Now get data for group. First the actual looking glass.
    with open(groupdata[router]) as file:
        filecontent = file.read()

    # Next the analysis.
    updated, freq, messages = prepare_bgp_analysis(current_app.config, asn=group)

    # Prepare template.
    dropdown_groups = list(looking_glass_files.keys())
    dropdown_routers = list(groupdata.keys())
    return render_template(
        "looking_glass.html",
        filecontent=filecontent,
        bgp_hints=messages,
        group=group, router=router,
        dropdown_groups=dropdown_groups, dropdown_routers=dropdown_routers,
        last_updated=updated, update_frequency=freq,
    )

@main_bp.route("/as-connections")
@main_bp.route("/as-connections/<int:group>")
@main_bp.route("/as-connections/<int:group>/<int:othergroup>")
def as_connections(group: int = None, othergroup: int = None):
    """Show the AS connections, optionally for selected groups only."""
    connections = parsers.parse_public_as_connections(
        current_app.config['LOCATIONS']['as_connections_public'])
    
    if connections:
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

        dropdown_matching_ases  = {conn[1]['asn'] for conn in selected_connections}
    else:
        all_ases = []
        selected_connections = None
        dropdown_matching_ases = None

    return render_template(
        "as_connections.html",
        connections=selected_connections,
        group=group,
        othergroup=othergroup,
        # All ASes
        dropdown_groups=all_ases,
        # Only matching ASes for first one.
        dropdown_others=dropdown_matching_ases,
    )

@main_bp.route("/krill")
def krill():
    """Allow access to krill, which is embedded as an iframe."""
    hostname = urlparse(request.base_url).hostname
    krill_url = current_app.config['KRILL_URL'].format(hostname=hostname)
    return render_template("krill.html", krill_url=krill_url)

@main_bp.route("/bgp-analysis")
@basic_auth.required
def bgp_analysis():
    """Return the full BGP analysis report."""
    updated, freq, messages = prepare_bgp_analysis(current_app.config)
    return render_template(
        "bgp_analysis.html", messages=messages,
        last_updated=updated, update_frequency=freq,
        )

@main_bp.route("/vpn")
@main_bp.route("/vpn/<router>")
@login_required
def vpn(router = None):
    """Show the vpn page for this user. Redirects to login page if no user is logged in."""
    ifs = find_all_ifs(group_number=get_current_users_group())

    # print(ifs)

    if_property_list=[
        {
            'name':'Peer1',
            'description':'Lorem ipsum dolor',
            'qr_image':url_for('static', filename='qr_code_missing.jpg')
        },
        {
            'name':'Peer2',
            'description':'Lorem ipsum dolor',
            'qr_image':url_for('static', filename='qr_code_missing.jpg')
        },
        {
            'name':'Peer3',
            'description':'Lorem ipsum dolor',
            'qr_image':url_for('static', filename='qr_code_missing.jpg')
        },
        {
            'name':'Peer4',
            'description':'Lorem ipsum dolor',
            'qr_image':url_for('static', filename='qr_code_missing.jpg')
        },
    ]

    return render_template(                                                                       
        "vpn.html",
        tabs=ifs.keys(),
        router=router,
        if_property_list=if_property_list
    )  

@main_bp.route("/login", methods=['GET', 'POST'])
def login():
    """Form for a user to log in."""
    form = LoginForm()

    if form.validate_on_submit():
        if(check_user_pwd(form.username.data, form.password.data)):
            login_user(User(form.username.data))
            # flash('Logged in successfully.', 'success')
            next = request.args.get('next')
            return redirect(next or url_for('main.index'))
        else:
            # flash('Wrong username or password', 'danger')
            pass

    return render_template(                                                                       
        "login.html", 
        form=form
    )  