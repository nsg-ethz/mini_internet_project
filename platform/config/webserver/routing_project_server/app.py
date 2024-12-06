"""A small web-server hosting all mini-internet tools.

The webserver needs access to the config and group directory,
or concretely to all paths present in the config under the key `LOCATIONS`.
Check the default config below for the list of paths.

Computing the connectivity matrix as well as the BGP analysis can take quite
a while, so it is possible to enabled `BACKGROUND_WORKERS` in the config to
start two background processes taking care of the updates in specified
intervals (`MATRIX_UPDATE_FREQUENCY`, `ANALYSIS_UPDATE_FREQUENCY`).

By default, these workers are started automatically when the app is created.
"""

import os
import traceback
from datetime import datetime as dt
from datetime import timezone
from multiprocessing import Process
from pathlib import Path
from time import sleep

from flask import Flask
from flask_basicauth import BasicAuth
from jinja2 import StrictUndefined

from .services.bgp_policy_analyzer import prepare_bgp_analysis
from.services.matrix import prepare_matrix
from .services.login import login_init
from .services.vpn import vpn_init

config_defaults = {
    'SECRET_KEY': os.urandom(32),
    'LOCATIONS': {
        'groups': '../../../groups',
        'as_config': "../../../config/AS_config.txt",
        "as_connections_public":
        "../../../config/aslevel_links_students.txt",
        "as_connections": "../../../config/aslevel_links.txt",
        "config_directory": "../../../config",
        "matrix": "../../../groups/matrix/connectivity.txt",
        "matrix_stats": "../../../groups/matrix/stats.txt",
        "vpn_folder":"wireguard",
        "vpn_passwd":"../../../groups/vpn_passwords.json",
        "vpn_db":"../../../groups/vpn.db"
    },
    'KRILL_URL': "http://{hostname}:3080/index.html",
    'BASIC_AUTH_USERNAME': 'admin',
    'BASIC_AUTH_PASSWORD': 'admin',
    'HOST': '127.0.0.1',
    'PORT': 8000,
    # Background processing for resource-intensive tasks.
    'BACKGROUND_WORKERS': False,
    'AUTO_START_WORKERS': True,
    'MATRIX_UPDATE_FREQUENCY': 30,  # seconds
    'ANALYSIS_UPDATE_FREQUENCY': 300,  # seconds
    'MATRIX_CACHE': '/tmp/cache/matrix.pickle',
    'ANALYSIS_CACHE': '/tmp/cache/analysis.db',
    'VPN_ENABLED':True,
    'VPN_NO_CLIENTS':1
}

# TODO: This is kind of ugly:
# add global extension
basic_auth = BasicAuth()

def create_app(config=None):
    # Create and configure the app.
    app = Flask(__name__)
    app.config.from_mapping(config_defaults)
    app.jinja_env.undefined = StrictUndefined

    if config is None:
        config = os.environ.get("SERVER_CONFIG", None)

    if config is not None and isinstance(config, dict):
        app.config.from_mapping(config)
    elif config is not None:
        app.config.from_pyfile(config)


    # Register Blueprints
    from .routes import main_bp
    app.register_blueprint(main_bp)

    # Initialize extensions
    login_init(app)
    basic_auth.init_app(app) 
    vpn_init(app)

    # Initialize template filters
    @app.template_filter()
    def format_timedelta_int(seconds):
        seconds = int(seconds)
        if seconds == 1:
            return "second"
        elif seconds == 60:
            return "minute"
        elif (seconds % 60) == 0:
            return f"{seconds // 60} minutes"
        return f"{seconds} seconds"

    @app.template_filter()
    def format_datetime(utcdatetime, format='%Y-%m-%d at %H:%M'):
        if utcdatetime.tzinfo is None:  # Attach tzinfo if needed
            utcdatetime = utcdatetime.replace(tzinfo=timezone.utc)
        localtime = utcdatetime.astimezone()
        return localtime.strftime(format)


    # Start workers if configured (and clear cache first).
    if app.config["BACKGROUND_WORKERS"] and app.config['AUTO_START_WORKERS']:
        Path(app.config["MATRIX_CACHE"]).unlink(missing_ok=True)
        Path(app.config["ANALYSIS_CACHE"]).unlink(missing_ok=True)
        start_workers(app.config)

    return app


# Worker functions.
# =================

def start_workers(config):
    """Create background processes"""
    processes = []

    pmatrix = Process(
        target=loop,
        args=(prepare_matrix, config['MATRIX_UPDATE_FREQUENCY'], config),
        kwargs=dict(worker=True)
    )
    pmatrix.start()
    processes.append(pmatrix)

    pbgp = Process(
        target=loop,
        args=(prepare_bgp_analysis,
              config['ANALYSIS_UPDATE_FREQUENCY'], config),
        kwargs=dict(worker=True)
    )
    pbgp.start()
    processes.append(pbgp)

    return processes


def loop(function, freq, *args, **kwargs):
    """Call function in loop. Freq must be in seconds."""
    print(f"Running worker `{function.__name__}` (every `{freq}s`).")
    while True:
        starttime = dt.utcnow()
        try:
            try:
                function(*args, **kwargs)
            except Exception as error:
                # Attach message to exception.
                raise RuntimeError(
                    f"Worker `{function.__name__}` crashed! Restarting."
                ) from error
        except:  # pylint: disable=bare-except
            traceback.print_exc()
        remaining_secs = freq - (dt.utcnow() - starttime).total_seconds()
        if remaining_secs > 0:
            sleep(remaining_secs)