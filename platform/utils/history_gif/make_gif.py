"""Read matrix status files and create gif."""
# pylint: disable=unspecified-encoding

import argparse
import json
import math
import os
import shutil
import subprocess
from datetime import datetime as dt
from functools import partial
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import List

import imageio as iio
import jinja2
from pygifsicle import optimize
from tqdm import tqdm
from tqdm.contrib.concurrent import process_map

# Local imports.
from utils import matrix, parsers

chrome_cmd = os.getenv("CHROME_CMD", "google-chrome")

scriptdir = Path(__file__).parent.absolute()
scriptdir_tmp = scriptdir / "tmp"
html_dir = scriptdir_tmp / "html"
png_dir = scriptdir_tmp / "png"
cache_dir = scriptdir_tmp / "cache"
default_config_dir = scriptdir.parent.parent / "config"
default_history_dir = scriptdir.parent.parent / "groups/history"


def main(config_dir, history_dir, approx_runtime, approx_holdtime, filter=False):
    """Parse all data and create the gif."""
    status_dicts = load_commits(history_dir, config_dir)
    assert len(status_dicts) > 0, "No status dicts found :("

    if filter and len(status_dicts) > 1:
        status_dicts = filter_status(status_dicts, stop_at_best=False)

    html_filenames = create_html(status_dicts)
    png_filenames = create_pngs(html_filenames)
    create_gif(
        png_filenames,
        approx_runtime_seconds=approx_runtime,
        extra_final_seconds=approx_holdtime,
    )


# =============================================================================
# Load history.
# =============================================================================


def load_commits(history_dir, config_dir):
    """Get matrix updates from commits to config_dir."""
    config_dir = Path(config_dir)
    # First, get all commits with updates to ./matrix/connectivity.txt
    # Get pairs of hashes and timestamps.
    revisions = run_git(
        history_dir,
        [
            "log",
            "--pretty=format:%H",
            # All commits that change configs or the matrix.
            "--",
            "configs/",
            "matrix/",
        ],
    ).split("\n")

    # TODO
    # revisions = revisions[:20]

    print(f"Found {len(revisions)} commits with config or matrix updates.")

    # Load general config
    as_data = parsers.parse_as_config(
        config_dir / "AS_config.txt",
        router_config_dir=config_dir,
    )
    connection_data = parsers.parse_as_connections(
        config_dir / "aslevel_links.txt",
    )

    data = []
    _loader = partial(
        load_revision_wrapper,
        history_dir=history_dir,
        as_data=as_data,
        connection_data=connection_data,
    )
    # data = list(map(_loader, revisions[:10]))
    data = process_map(
        _loader, revisions, desc="loading revisions", max_workers=32, chunksize=1
    )
    data = [item for item in data if item is not None]
    print(f"{len(data)}/{len(revisions)} revisions are valid.")

    # Check for changes to validity and connectivity.
    data = sorted(data, key=lambda item: item["last_updated"])
    unique = data[:1]
    for item in tqdm(data[1:], desc="checking diffs"):
        if (item["connectivity"] != unique[-1]["connectivity"]) or (
            item["validity"] != unique[-1]["validity"]
        ):
            unique.append(item)

    print(f"Loaded {len(unique)} status dicts.")
    return unique


def load_revision_wrapper(revision, *args, **kwargs):
    """We experiences an (yet unexplained error) with weird commits.

    These contain data about the wrong topology. We are not sure why they are
    there, and why they exists only for certain days, but it will cause the
    code to crash. We exclude them.
    """
    cache_dir.mkdir(parents=True, exist_ok=True)
    invalid_file = cache_dir / f"{revision}_invalid.json"
    if invalid_file.is_file():
        return None
    try:
        return load_revision(revision, *args, **kwargs)
    except AssertionError as error:
        with open(invalid_file, "w") as file:
            file.write(str(error))
        return None


def load_revision(revision, *, history_dir, as_data, connection_data):
    """Load connectivity and validity from a specific git revision."""
    history_dir = Path(history_dir)
    cache_dir.mkdir(parents=True, exist_ok=True)
    # Try to return from cache.
    try:
        with open(cache_dir / f"{revision}.json") as file:
            raw = json.load(file)
            # Convert timestamp to datetime object.
            raw["last_updated"] = dt.fromisoformat(raw["last_updated"])
            return raw
    except FileNotFoundError:
        pass

    all_ases = set(k for k, v in as_data.items() if v["type"] == "AS")

    # use git worktree to get files in a temporary directory.
    with TemporaryDirectory() as tmpdirname:
        tmpdir = Path(tmpdirname)
        run_git(history_dir, ["worktree", "add", tmpdir, revision])

        # Load data
        connectivity_data = parsers.parse_matrix_connectivity(
            tmpdir / "matrix" / "connectivity.txt"
        )
        found_ases = set(
            asn for (src, dst, _) in connectivity_data for asn in (src, dst)
        )
        assert found_ases == all_ases

        looking_glass_data = parsers.parse_looking_glass_json(tmpdir / "configs")
        # Bug in 2024: TA ASes are not saved correctly, can't check this.
        # assert all_ases.issubset(set(looking_glass_data))

        # Commit timestamp
        timestamp = run_git(
            tmpdir, ["log", "-1", "--format=%ad", "--date=iso-strict"]
        ).strip()

    results = {
        "connectivity": matrix.check_connectivity(as_data, connectivity_data),
        "validity": matrix.check_validity(as_data, connection_data, looking_glass_data),
        "last_updated": timestamp,
    }

    # Cache results
    with open(cache_dir / f"{revision}.json", "w") as file:
        json.dump(results, file)

    # convert timestamp to datetime and return
    results["last_updated"] = dt.fromisoformat(results["last_updated"])
    return results


def run_git(config_dir, command):
    """Run a git command.

    We use sudo as this i needed for the default history dir. Maybe adjust?
    """
    base_command = ["git", "-C", str(config_dir)]
    # Show command.
    # print(" ".join(base_command + command))
    return subprocess.run(
        base_command + command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    ).stdout.decode()


# =============================================================================
# Data analysis and filtering.
# =============================================================================


def filter_status(status_dicts, stop_at_best=True):
    """Clean up which statuses to use."""
    print("Ending with best state and filtering changes below 1 percent.")
    valid, invalid, failure = zip(
        *[analyze(status_dict) for status_dict in status_dicts]
    )
    if stop_at_best:
        # Use lowest failure as last index.
        last_index = len(failure) - failure[::-1].index(min(failure)) - 1
        status_dicts = status_dicts[:last_index]

    # Also filter out items with very little change
    min_change = 1
    absolute_change = [
        abs(delta_valid) + abs(delta_invalid)
        for delta_valid, delta_invalid in zip(
            compute_change(valid), compute_change(invalid)
        )
    ]
    status_dicts = [
        status_dict
        for status_dict, change in zip(status_dicts, absolute_change)
        if change >= min_change
    ]
    print(len(status_dicts), "status dicts after filter.")
    return status_dicts


def analyze(status):
    """Summarize valid, invalid, failure."""
    valid, invalid, failure = 0, 0, 0
    for src, dsts in status["connectivity"].items():
        for dst, connected in dsts.items():
            if connected:
                # We have connectivity, now check if valid.
                # If validity could not be checked, assume valid.
                if status["validity"].get(src, {}).get(dst, True):
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
    return valid, invalid, failure


def compute_change(data, first_value=0):
    """Compute delta between values in data."""
    return [item - prev for item, prev in zip(data, [first_value, *data[:-1]])]


def sort_numeric(list_of_strings):
    return sorted(list_of_strings, key=int)  # Convert to int before sorting.


# =============================================================================
# Render html.
# =============================================================================


def create_html(status_dicts: List[dict]):
    """Render html files."""
    jinja_env = jinja2.Environment(loader=jinja2.FileSystemLoader(str(scriptdir)))
    jinja_env.filters["sortnum"] = sort_numeric
    matrix_template = jinja_env.get_template("matrix.html")
    html_dir.mkdir(parents=True, exist_ok=True)

    filenames = []
    for item in tqdm(status_dicts, desc="prepare html"):
        key = item["last_updated"].strftime("%Y%m%d-%H%M%S") + ".html"
        filename = html_dir / key
        if not filename.is_file():
            result = render(matrix_template, item)
            with open(filename, "w") as file:
                file.write(result)
        filenames.append(filename)

    return filenames


def render(template, status):
    """Generate html file from json dict."""

    valid, invalid, failure = analyze(status)

    return template.render(
        connectivity=status["connectivity"],
        validity=status["validity"],
        valid=valid,
        invalid=invalid,
        failure=failure,
    )


# =============================================================================
# Create pngs.
# =============================================================================


def create_pngs(filenames, size=(2048, 2048), n_jobs=16):
    """Create pngs from html."""
    out = png_dir / "x".join((str(i) for i in size))
    out.mkdir(parents=True, exist_ok=True)
    funcargs = []
    all_pngs = []
    for filename in filenames:
        png_file = out / filename.name.replace(".html", ".png")
        all_pngs.append(png_file)
        if not png_file.is_file():
            funcargs.append((filename, png_file, size))

    # Parallelize with status bar :)
    process_map(
        take_screenshot,
        funcargs,
        desc="take screenshots",
        max_workers=n_jobs,
        chunksize=1,
    )
    return sorted(all_pngs)


def take_screenshot(args):
    """Take screenshot. Create a user-data-dir to enable multiprocessing."""
    input_path, output_path, size = args
    userdir = Path(cache_dir) / Path(input_path).stem
    userdir.mkdir(parents=True, exist_ok=False)
    command = [
        chrome_cmd,
        "--headless=new",  # better results?
        "--disable-gpu",
        "--log-level=3",
        "--hide-scrollbars",
        # "--no-sandbox",  # so we can run as root as well.
        f"--user-data-dir={userdir}",
        f"--screenshot={output_path}",
        f"--window-size={size[0]},{size[1]}",
        f"{input_path}",
    ]
    try:
        subprocess.run(
            command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True
        )
    except subprocess.CalledProcessError as error:
        print(" ".join(command))
        raise error
    finally:
        shutil.rmtree(userdir)


# =============================================================================
# Create gif.
# =============================================================================


def create_gif(
    filenames,
    approx_runtime_seconds=12,
    extra_final_seconds=3,
):
    """Create a gif! :)"""
    gif_path = scriptdir / "matrix.gif"
    opt_path = scriptdir / "matrix_opt.gif"

    # Alternative: Set frame times based on commit timestamps.
    # Didn't really improve, so I use the simple version.
    # # For each frame, get the duration.
    # timestamps = [
    #     dt.strptime(filename.name, "%Y%m%d-%H%M%S.png")
    #     for filename in filenames
    # ]

    # total_duration = max(timestamps) - min(timestamps)
    # all_progress = [
    #     (timestamp - min(timestamps)) / total_duration
    #     for timestamp in timestamps
    # ]
    # seconds = [
    #     progress * (total_seconds - final_seconds)
    #     for progress in all_progress
    # ]
    # all_durations = [
    #     # gifs only support hundreds of a second.
    #     round(next_ts - ts, 2)
    #     for ts, next_ts in zip(seconds, seconds[1:])
    # ] + [final_seconds]

    # Simple fixed time
    # gifs only support hundreds of a second., round to nearest.
    frame_seconds = round(approx_runtime_seconds / len(filenames), 2)
    print(f"Using {frame_seconds} seconds per frame.")
    print(f"Total runtime: {frame_seconds * len(filenames)} seconds.")
    print(f"Extra seconds for final frame: {extra_final_seconds}.")
    all_durations = [frame_seconds] * len(filenames)
    all_durations[-1] += extra_final_seconds

    # Skip frames with 0 time, if any.
    durations = [duration for duration in all_durations if duration]
    # Now actually load files.

    frames = [
        iio.v3.imread(file) for file, duration in zip(filenames, durations) if duration
    ]

    print("create gif.")
    iio.plugins.freeimage.download()  # Not sure if still needed.
    iio.v3.imwrite(
        gif_path,
        frames,
        plugin="GIF-FI",
        duration=durations,
        palettesize=32,
        quantizer="nq",  # "wu" is much faster but messes up text color.
    )
    print("optimize gif.")
    optimize(
        gif_path,
        opt_path,
        colors=32,  # More than enough for shades of grey etc.
        options=["--scale=0.5"],  # Reduces size a lot.
    )


# =============================================================================
# Main.
# =============================================================================

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Create a gif of the mini internet's state over time."
    )
    parser.add_argument(
        "--config",
        type=Path,
        help="Directory with mini-internet config.",
        default=default_config_dir,
    )
    parser.add_argument(
        "--history",
        type=Path,
        help="Directory with history (in commits).",
        default=default_history_dir,
    )
    parser.add_argument(
        "--run", type=int, help="Approximate runtime of the gif in seconds.", default=12
    )
    parser.add_argument(
        "--hold",
        type=int,
        help="Approximate hold time of final frame in seconds " "after gif runtime.",
        default=3,
    )
    parser.add_argument(
        "--filter",
        action="store_true",
        help="Filter status dicts to only show larger changes.",
    )
    args = parser.parse_args()

    main(args.config, args.history, args.run, args.hold, args.filter)
