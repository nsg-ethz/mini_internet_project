import json
import os
import shlex
import time
from datetime import datetime as dt
from datetime import timedelta
from random import shuffle
from subprocess import PIPE, Popen
import traceback

update_frequency_envvar = 'UPDATE_FREQUENCY'
default_update_frequency_seconds = 60
restart_delay_seconds = 60

while True:
    try:
        # Reload the config at every loop.
        # It takes almost no time, and we can react to changes in the config.
        as_list = {}
        with open('destination_ips.txt', 'r') as fd:
            for line in fd.readlines():
                linetab = line.rstrip('\n').split(' ')
                asn = int(linetab[0])
                dest_ip = linetab[1]
                as_list[asn] = dest_ip

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
            div = int(asn/100)
            if mod < 10:
                mod = "0"+str(mod)
            if div < 10:
                div = "0"+str(div)

        print("Starting the ping measurements.")
        start_ts = dt.utcnow()

        # Perform the ping measurements
        for from_g in sorted(as_list.keys()):
            proc_dic[from_g] = {}
            tmp_to_g = list(as_list.keys())
            shuffle(tmp_to_g)
            for to_g in tmp_to_g:

                if to_g >= from_g:

                    cmd = ("nping "
                           + " --source-ip "+str(from_g)
                           + ".0.198.2 --dest-ip "
                           + str(as_list[to_g])
                           + " --interface group_"+str(from_g)
                           + " -c 1 --tcp --delay 250ms")
                    # print(cmd)
                    proc_dic[from_g][to_g] = Popen(
                        shlex.split(cmd), stdout=PIPE, text=True)
                    # Sleep one millisecond to not spawn too many processes
                    # at once.
                    time.sleep(0.001)

            for to_g in proc_dic[from_g]:
                pout = proc_dic[from_g][to_g].communicate()[0]
                try:
                    output_tmp = pout.split('\n')[3]
                except:
                    print(f"Error with output for ping {from_g}->{to_g}.")
                    output_tmp = ""

                if "RCVD" in output_tmp and 'ICMP' not in output_tmp:
                    co_dic[from_g][to_g] = True
                    co_dic[to_g][from_g] = True
                else:
                    co_dic[from_g][to_g] = False
                    co_dic[to_g][from_g] = False

        # Check environment for update frequency, use default otherwise.
        update_frequency = timedelta(seconds=int(os.getenv(
            update_frequency_envvar, default_update_frequency_seconds)))
        current_time = dt.utcnow()
        update_time = dt.utcnow() - start_ts

        print("Writing stats to file.")
        with open('stats.txt', 'w') as file:
            json.dump({
                'current_time': current_time.isoformat(),
                'update_time': update_time.total_seconds(),
                'update_frequency': update_frequency.total_seconds(),
            }, file)

        print("Writing results to file.")
        with open('connectivity.txt', 'w') as file:
            for from_g in co_dic:
                for to_g in co_dic:
                    file.write(f'{from_g}\t{to_g}\t{co_dic[from_g][to_g]}\n')

        # Re-compute update time to account for file writing.
        update_time = dt.utcnow() - start_ts
        print("Update time: ", update_time)
        if update_time < update_frequency:
            delta = update_frequency - update_time
            print(f"Sleeping for {delta.total_seconds():.2f} seconds")
            time.sleep(delta.total_seconds())
    except:  # pylint: disable=bare-except
        print("An error occured!")
        # print stacktrace without raising
        traceback.print_exc()

        print(
            f"Sleeping for {restart_delay_seconds} seconds before restarting.")
        time.sleep(restart_delay_seconds)
