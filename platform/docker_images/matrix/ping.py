import json
import os
import shlex
import time
from datetime import datetime as dt
from datetime import timedelta
from random import shuffle
from subprocess import Popen, DEVNULL
import traceback

update_frequency_envvar = "UPDATE_FREQUENCY"
default_update_frequency_seconds = 60
restart_delay_seconds = 60

ping_flags_envvar = "PING_FLAGS"
default_ping_flags = "-c 3 -i 0.01"  # Three pings, 10ms interval.

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

        # Connectivity dictionnary
        co_dic = {}
        # Ping processes dic
        proc_dic = {}

        # Connectivity dictionnary initializatin
        for from_g in as_list:
            co_dic[from_g] = {}
            for to_g in as_list:
                co_dic[from_g][to_g] = False

        for asn in as_list:
            mod = int(asn % 100)
            div = int(asn / 100)
            if mod < 10:
                mod = "0" + str(mod)
            if div < 10:
                div = "0" + str(div)

        print("Starting the ping measurements.")
        start_ts = dt.utcnow()

        # Perform the ping measurements
        for from_g in sorted(as_list.keys()):
            proc_dic[from_g] = {}
            tmp_to_g = list(as_list.keys())
            shuffle(tmp_to_g)
            for to_g in tmp_to_g:
                if to_g >= from_g:
                    dst_ip = as_list[to_g]
                    cmd = f"ping -I group_{from_g} {ping_flags} {dst_ip}"
                    proc_dic[from_g][to_g] = Popen(
                        shlex.split(cmd), stdout=DEVNULL)
                    # Sleep one millisecond to limit spawn rate of processes.
                    time.sleep(0.001)

        for from_g in proc_dic:
            for to_g in proc_dic[from_g]:
                # Wait for the process to finish
                proc_dic[from_g][to_g].communicate()
                # Ping returns 0 if it worked, 1 if no packets arrived,
                # and 2 if there was another error.
                # https://linux.die.net/man/8/ping
                returncode = proc_dic[from_g][to_g].returncode
                assert returncode < 2, "Ping encountered an error!"
                ping_worked = returncode == 0
                co_dic[from_g][to_g] = ping_worked
                co_dic[to_g][from_g] = ping_worked

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
