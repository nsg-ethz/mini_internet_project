from subprocess import Popen, PIPE
import shlex
import time
from random import shuffle
from datetime import datetime as dt, timedelta

update_frequency = timedelta(minutes=1)

while True:
    # Reload the config at every loop.
    # It takes almost no time, and we can react to changes in the config.
    as_list = {}
    with open('destination_ips.txt', 'r') as fd:
        for line in fd.readlines():
            linetab = line.rstrip('\n').split(' ')
            asn = int(linetab[0])
            dest_ip = linetab[1]
            as_list[asn] = dest_ip

    # Load the MAC addresses of the mgt interface on HOUS
    mac_dic = {}
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

        mac_dic[asn] = "aa:11:11:11:"+str(div)+":"+str(mod)

    def interfaces_up():
        """Return True if all interfaces are up."""
        for from_g in sorted(as_list.keys()):
            interface = f"group_{from_g}"
            cmd = f"ip link show {interface}"
            proc = Popen(shlex.split(cmd), stdout=PIPE, text=True)
            output = proc.communicate()[0]
            if "UP" not in output:
                print(f"Interface {interface} is not up yet.")
                return False
            print(f"Interface {interface} is up.")
        return True

    while not interfaces_up():
        print("Waiting for the interfaces to be up, sleeping 5 seconds.")
        time.sleep(5)

    print("Starting the ping measurements.")

    start_ts = dt.utcnow()

    # Perform the ping measurements
    for from_g in sorted(as_list.keys()):
        proc_dic[from_g] = {}
        tmp_to_g = list(as_list.keys())
        shuffle(tmp_to_g)
        for to_g in tmp_to_g:

            if to_g >= from_g:

                cmd = "nping --dest-mac "+mac_dic[from_g]+" --source-ip "+str(from_g)+".0.198.2 --dest-ip "+str(
                    as_list[to_g])+" --interface group_"+str(from_g)+" -c 1 --tcp --delay 250ms"
                # print(cmd)
                proc_dic[from_g][to_g] = Popen(
                    shlex.split(cmd), stdout=PIPE, text=True)
                # Sleep one millisecond to avoid spawning too many processes
                # at once.
                time.sleep(0.001)

        for to_g in proc_dic[from_g]:

            output_tmp = proc_dic[from_g][to_g].communicate()[0].split('\n')[3]
            if "RCVD" in output_tmp and 'ICMP' not in output_tmp:
                co_dic[from_g][to_g] = True
                co_dic[to_g][from_g] = True
                # print("Connectivity Between "+str(from_g)+" and "+str(to_g))
            else:
                co_dic[from_g][to_g] = False
                co_dic[to_g][from_g] = False
                # print("No Connectivity Between "+str(from_g)+" and "+str(to_g))
                # print(output_tmp)
                # print output_tmp.split('\n')[3]

    print("Writing results to file")
    with open('connectivity.txt', 'w') as fd_out:
        for from_g in co_dic:
            for to_g in co_dic:
                fd_out.write(f'{from_g}\t{to_g}\t{co_dic[from_g][to_g]}\n')

    update_time = dt.utcnow() - start_ts
    print("Update time: ", update_time)
    if update_time < update_frequency:
        delta = update_frequency - update_time
        print(f"Sleeping for {delta.total_seconds():.2f} seconds")
        time.sleep(delta.total_seconds())
