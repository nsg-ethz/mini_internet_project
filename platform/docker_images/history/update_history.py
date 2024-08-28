"""Run the update_history.sh script in a loop.

Every 10s, re-load environment variables to check for changes.
10s is also the minimum time between runs of the update_history.sh script.
"""

import os
import subprocess
import time
from datetime import datetime as dt
from datetime import timedelta
from pathlib import Path

script_dir = Path(__file__).parent.absolute()
script_file = str(script_dir / "update_history.sh")
last_update = None
next_update = None
last_check = None
last_check_frequency = None
last_update_frequency = None

argument_defaults = {
    "OUTPUT_DIR": "./output",
    "MATRIX_DIR": "../../groups/matrix",
    "TIMEOUT": "300s",
    "GIT_USER": "Mini-Internet History",
    "GIT_EMAIL": "mini@internet.com",
    "GIT_URL": "",
    "GIT_BRANCH": "main",
    "FORGET_BINARIES": "true",
}

while True:
    # Parse environment.
    check_frequency = float(os.getenv("CHECK_FREQUENCY", 10))
    if check_frequency != last_check_frequency:
        print(f"Check frequency: {check_frequency:.2f}s")
        last_check_frequency = check_frequency
    update_frequency = float(os.getenv("UPDATE_FREQUENCY", 60))
    if update_frequency != last_update_frequency:
        print(f"Update frequency: {update_frequency:.2f}s")
        last_update_frequency = update_frequency
        if last_update is not None:
            next_update = last_update + timedelta(seconds=update_frequency)
            print(f"New next update in {next_update - dt.now()}.")

    args = {k: os.getenv(k, v) for k, v in argument_defaults.items()}

    Path(args["OUTPUT_DIR"]).mkdir(parents=True, exist_ok=True)
    assert Path(args["MATRIX_DIR"]).is_dir()
    assert args["FORGET_BINARIES"] in ["true", "false"]

    if (next_update is None) or (dt.now() > next_update):
        last_update = last_check = dt.now()
        print(f"{last_update}: Updating history with arguments:")
        for k, v in args.items():
            print(f"{k}: {v}")
        subprocess.run([script_file, *args.values()], check=False)
        print("Completed in", dt.now() - last_update)

        next_update = last_update + timedelta(seconds=update_frequency)
        print(f"Next update in {next_update - dt.now()}.")

    next_check = last_check + timedelta(seconds=check_frequency)
    diff = (next_check - dt.now()).total_seconds()
    last_check = dt.now()
    if diff > 0:
        time.sleep(diff)
