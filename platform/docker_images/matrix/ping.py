import json
import os
import shlex
import time
from datetime import datetime as dt
from datetime import timedelta
from random import shuffle
from subprocess import Popen, DEVNULL, PIPE
from concurrent.futures import ProcessPoolExecutor
import traceback

update_frequency_envvar = "UPDATE_FREQUENCY"
default_update_frequency_seconds = 60
restart_delay_seconds = 60

ping_flags_envvar = "PING_FLAGS"
default_ping_flags = "-c 3 -i 0.01"  # Three pings, 10ms interval.

concurrent_pings_envvar = "CONCURRENT_PINGS"
default_concurrent_pings = 100

def run_ping(cmd):
    """Runs ping, returns True if success, False if not; or error string."""
    process = Popen(shlex.split(cmd), stdout=DEVNULL, stderr=PIPE)
    _, stderr = process.communicate()
    # Ping returns 0 if it worked, 1 if no packets arrived,
    # and 2 if there was another error.
    # https://linux.die.net/man/8/ping
    if process.returncode == 0:
        return True
    elif process.returncode == 1:
        return False
    else:
        return f"Error: {stderr.decode('utf-8')}"

while True:
    try:
        # Reload the config at every loop.
        # It takes almost no time, and we can react to changes in the config.
        as_list = {}
        with open("destination_ips.txt", "r") as fd:
            for line in fd.readlines():
                linetab = line.rstrip("\n").split(" ")
                asn = int(linetab[0])
                dest_ip = linetab[1]
                as_list[asn] = dest_ip

        # Also reload environment variables for quick reconfiguration.
        ping_flags = str(os.getenv(ping_flags_envvar, default_ping_flags))
        update_frequency = timedelta(
            seconds=int(
                os.getenv(update_frequency_envvar, default_update_frequency_seconds)
            )
        )
        concurrent_pings = int(
            os.getenv(concurrent_pings_envvar, default_concurrent_pings))

        # Initialize connectivity dictionary
        co_dic = {}
        for from_g in as_list:
            co_dic[from_g] = {}
            for to_g in as_list:
                co_dic[from_g][to_g] = False

        print("Starting the ping measurements.")
        start_ts = dt.utcnow()

        # Perform the ping measurements
        pairs = []
        jobs = []

        for from_g in sorted(as_list.keys()):
            tmp_to_g = list(as_list.keys())
            shuffle(tmp_to_g)
            for to_g in tmp_to_g:
                if to_g >= from_g:
                    dst_ip = as_list[to_g]
                    cmd = f"ping -I group_{from_g} {ping_flags} {dst_ip}"
                    pairs.append((from_g, to_g))
                    jobs.append(cmd)

        with ProcessPoolExecutor(max_workers=concurrent_pings) as executor:
            results = executor.map(run_ping, jobs)

        errors = []
        for (from_g, to_g), result in zip(pairs, results):
            if isinstance(result, bool):
                success = result
            else:
                success = False
                errors.append(result)
            co_dic[from_g][to_g] = success
            co_dic[to_g][from_g] = success

        if errors:
            print("Some ping commands failed:")
            for error in errors:
                print(error)

        print("Writing stats to file.")
        current_time = dt.utcnow()
        update_time = dt.utcnow() - start_ts
        with open("stats.txt", "w") as file:
            json.dump(
                {
                    "current_time": current_time.isoformat(),
                    "update_time": update_time.total_seconds(),
                    "update_frequency": update_frequency.total_seconds(),
                },
                file,
            )

        print("Writing results to file.")
        with open("connectivity.txt", "w") as file:
            for from_g in co_dic:
                for to_g in co_dic:
                    file.write(f"{from_g}\t{to_g}\t{co_dic[from_g][to_g]}\n")

        # Re-compute update time to account for file writing.
        update_time = dt.utcnow() - start_ts
        print("Update time: ", update_time)
        if update_time < update_frequency:
            delta = update_frequency - update_time
            print(f"Sleeping for {delta.total_seconds():.2f} seconds")
            time.sleep(delta.total_seconds())
    except Exception:
        print("An error occured!")
        traceback.print_exc()  # print stacktrace without raising

        print(f"Sleeping for {restart_delay_seconds} seconds before restarting.")
        time.sleep(restart_delay_seconds)
