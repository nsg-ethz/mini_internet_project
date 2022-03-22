#!/usr/bin/python3
"""Create and run the app using bjoern."""

import sys

import bjoern

from routing_project_server import create_app

if __name__ == "__main__":
    if len(sys.argv) > 2:
        config = sys.argv[1]
        print(config)
    else:
        config = None

    app = create_app(config)
    host = app.config['HOST']
    port = app.config['PORT']
    print(f"Running server on `{host}:{port}`.")
    bjoern.run(app, host, port)
