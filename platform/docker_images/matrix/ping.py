from subprocess import Popen, PIPE
import shlex
from time import sleep
import time
import random
from random import shuffle

as_list = {}

with open('destination_ips.txt') as fd:
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

    mod = asn%100
    div = asn/100

    if mod < 10:
        mod = "0"+str(mod)
    if div < 10:
        div = "0"+str(div)

    mac_dic[asn] = "aa:11:11:11:"+str(div)+":"+str(mod)

while True:

    # Perform the ping measurements
    for from_g in sorted(as_list.keys()):
        proc_dic[from_g] = {}
        tmp_to_g = list(as_list.keys())
        shuffle(tmp_to_g)
        for to_g in tmp_to_g:

            if to_g >= from_g:

                cmd = "nping --dest-mac "+mac_dic[from_g]+" --source-ip "+str(from_g)+".0.198.2 --dest-ip "+str(as_list[to_g])+" --interface group_"+str(from_g)+" -c 3 --delay 250ms"
                print cmd
                proc_dic[from_g][to_g] = Popen(shlex.split(cmd), stdout=PIPE)
                time.sleep(0.05)

        for to_g in proc_dic[from_g]:

            output_tmp = proc_dic[from_g][to_g].communicate()[0]
            if "Echo reply" in output_tmp:
                co_dic[from_g][to_g] = True
                print "Connectivity Between "+str(from_g)+" and "+str(to_g)
            else:
                co_dic[from_g][to_g] = False
                print "No Connectivity Between "+str(from_g)+" and "+str(to_g)
                print output_tmp
                #print output_tmp.split('\n')[3]
        # sleep(0.1)




    # # success_symbol = 'glyphicon glyphicon-ok text-success'
    # # fail_symbol = 'glyphicon glyphicon-remove text-danger'
    # success_symbol = 'connectivity-success'
    # fail_symbol = 'connectivity-failure'
    #
    # fd = open('final.html', 'r')
    # html_str = fd.read()
    # fd.close()
    #
    # # Modify the html file accordingly
    # for from_g in as_list:
    #     for to_g in as_list:
    #         if co_dic[from_g][to_g]:
    #             html_str = html_str.replace('<!-- BIN:'+str(from_g)+'-'+str(to_g)+' -->', '"'+success_symbol+'"')
    #         else:
    #             html_str = html_str.replace('<!-- BIN:'+str(from_g)+'-'+str(to_g)+' -->', '"'+fail_symbol+'"')
    #
    # html_str = html_str.replace('TIME', time.ctime())
    #
    # fd = open('matrix.html', 'w')
    # fd.write(html_str)
    # fd.close()
