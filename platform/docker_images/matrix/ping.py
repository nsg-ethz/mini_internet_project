from subprocess import Popen, PIPE
import shlex
from time import sleep
import time
import random
from random import shuffle
import datetime

as_list = {}

def update_matrix(as_list, co_dic, t):
    fd = open('matrix.html', 'w')

    fd.write('<!DOCTYPE html>\n')
    fd.write('<html lang="en">\n')
    fd.write('<head>\n')
    fd.write('\t<meta charset="utf-8">\n')
    fd.write('\t<meta http-equiv="X-UA-Compatible" content="IE=edge">\n')
    fd.write('\t<meta name="viewport" content="width=device-width, initial-scale=1>\n')
    fd.write('\t<link rel="shortcut icon" href="favicon.ico"/>\n')
    fd.write('\t<meta name="description" content="Communication Networks">\n')
    fd.write('\t<meta name="author" content="Laurent Vanbever">\n')
    fd.write('\t\n')
    fd.write('\t<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">\n')
    fd.write('\t<meta http-equiv="Pragma" content="no-cache">\n')
    fd.write('\t<meta http-equiv="Expires" content="0">\n')
    fd.write('\t<meta http-equiv="refresh" content="30" />\n')
    fd.write('\t\n')
    fd.write('\t<title>Communication Networks</title>\n')
    fd.write('\t<link href="css/bootstrap.min.css" rel="stylesheet">\n')
    fd.write('\t<link href="css/bootstrap-theme.min.css" rel="stylesheet">\n')
    fd.write('\t<link href="css/custom.css" rel="stylesheet">\n')
    fd.write('</head>\n')
    fd.write('\t\n')
    fd.write('<body role="document">\n')
    fd.write('\t\n')
    fd.write('\t<div class="container" role="main">\n')
    fd.write('\t\n')
    fd.write('\t\t<div class="page-header">\n')
    fd.write('\t\t\t<h3>Internet Project: Connectivity Matrix</h3>\n')
    fd.write('\t\t</div>\n')
    fd.write('\t\n')
    fd.write('\t\t<p>\n')
    fd.write('\t\t\tThis connectivity matrix indicates the networks that each group \
    can (<span class="connectivity-success">&nbsp;&nbsp;&nbsp;</span>) or cannot reach \
    (<span class="connectivity-failure">&nbsp;&nbsp;&nbsp;</span>). \
    It takes '+str(int(t))+'s to fully update the matrix. Last upload at '+str(datetime.datetime.now().strftime("%m/%d/%Y, %H:%M:%S"))+'\n')
    fd.write('\t\t</p>\n')
    fd.write('\t\n')
    fd.write('\t\t<div class="progress_container"></div>\n')
    fd.write('\t\n')
    fd.write('\t\t<table class="table table-striped table-bordered">\n')
    fd.write('\t\t\t<thread>\n')
    fd.write('\t\t\t\t<td></td>\n')

    for asn in sorted(as_list.keys()):
        if asn < 100:
            fd.write('\t\t\t\t<td style="width: 15px;"> '+" ".join(str(asn))+'</td>\n')
        else:
            fd.write('\t\t\t\t<td style="width: 15px;">'+" ".join(str(asn))+'</td>\n')

    fd.write('\t\t\t</thead>\n')

    for asn_from in sorted(as_list.keys()):
        fd.write('\t\t\t<tr>\n')
        fd.write('\t\t\t<td>G'+str(asn_from)+'</td>\n')
        for asn_to in sorted(as_list.keys()):
            if co_dic[asn_from][asn_to]:
                fd.write('\t\t\t\t<td class="connectivity-success" title="AS{} <-> AS{}: Reachable"><span class="glyphicon glyphicon-ok text-success"></td>\n'.format(asn_from, asn_to))
            else:
                fd.write('\t\t\t\t<td class="connectivity-failure" title="AS{} <-> AS{}: Not Reachable"><span class="glyphicon glyphicon-remove text-danger"></td>\n'.format(asn_from, asn_to))
        fd.write('\t\t\t</tr>\n')

    # fd.write('\t\t\t<thread>\n')
    # fd.write('\t\t\t\t<td></td>\n')
    #
    # for asn in sorted(as_list.keys()):
    #     fd.write('\t\t\t\t<td>'+str(asn)+'</td>\n')
    #
    # fd.write('\t\t\t</thead>\n')
    fd.write('\t\t</table>\n')

    fd.write('\t\n')
    fd.write('\t</div> <!-- container -->\n')
    fd.write('\t<!-- Bootstrap core JavaScript\n')
    fd.write('\t================================================== -->\n')
    fd.write('\t<!-- Placed at the end of the document so the pages load faster -->\n')
    fd.write('\t<script src="https://ajax.googleapis.com/ajax/libs/jquery/1.11.1/jquery.min.js"></script>\n')
    fd.write('\t<script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.5/js/bootstrap.min.js"></script>\n')
    fd.write('\t\n')
    fd.write('\t<script>\n')
    fd.write('\t$(function(){\n')
    fd.write('\t\tvar num_reachable   = $("table").find("td.connectivity-success").length;\n')
    fd.write('\t\tvar num_unreachable = $("table").find("td.connectivity-failure").length;\n')
    fd.write('\t\tvar num_total = num_reachable + num_unreachable;\n')
    fd.write('\t\tvar perc_reachable = num_reachable / num_total * 100;\n')
    fd.write('\t\tvar perc_unreachable = num_unreachable / num_total * 100;\n')
    fd.write('\t\t$(".progress_container").html("<div class=\\\"progress\\\"><div class=\\\"progress-bar progress-bar-success\\\" role=\\\"progressbar\\\" style=\\\"width:"+perc_reachable+"%\\\">Reachable ("+Math.round(perc_reachable)+"%)</div><div class=\\\"progress-bar progress-bar-danger\\\" role=\\\"progressbar\\\" style=\\\"width:"+perc_unreachable+"%\\\">Not reachable ("+Math.round(perc_unreachable)+"%)</div></div>");\n')
    fd.write('\t})\n')
    fd.write('\t</script>\n')
    fd.write('\t\n')
    fd.write('\t<script>\n')
    fd.write('\t$(document).ready(function(){\n')
    fd.write('\t\t$(\'[data-toggle="popover"]\').popover();\n')
    fd.write('\t});\n')
    fd.write('\t</script>\n')
    fd.write('\t\n')
    fd.write('</body>\n')
    fd.write('</html>\n')

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

update_time = 999

while True:

    start_ts = time.time()

    # Perform the ping measurements
    for from_g in sorted(as_list.keys()):
        proc_dic[from_g] = {}
        tmp_to_g = list(as_list.keys())
        shuffle(tmp_to_g)
        for to_g in tmp_to_g:

            if to_g >= from_g:

                cmd = "nping --dest-mac "+mac_dic[from_g]+" --source-ip "+str(from_g)+".0.198.2 --dest-ip "+str(as_list[to_g])+" --interface group_"+str(from_g)+" -c 1 --tcp --delay 250ms"
                print cmd
                proc_dic[from_g][to_g] = Popen(shlex.split(cmd), stdout=PIPE)
                print 'sleep ', (113-from_g)*0.001
                time.sleep((113-from_g)*0.001)

        for to_g in proc_dic[from_g]:

            output_tmp = proc_dic[from_g][to_g].communicate()[0].split('\n')[3]
            if "RCVD" in output_tmp and 'ICMP' not in output_tmp:
                co_dic[from_g][to_g] = True
                co_dic[to_g][from_g] = True
                print "Connectivity Between "+str(from_g)+" and "+str(to_g)
            else:
                co_dic[from_g][to_g] = False
                co_dic[to_g][from_g] = False
                print "No Connectivity Between "+str(from_g)+" and "+str(to_g)
                print output_tmp
                #print output_tmp.split('\n')[3]
        # sleep(0.1)

        update_matrix(as_list, co_dic, update_time)


    update_time = time.time() - start_ts


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
    # for from_g in sorted(as_list.keys()):
    #     for to_g in sorted(as_list.keys()):
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
