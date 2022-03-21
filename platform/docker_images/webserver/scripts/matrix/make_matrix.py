import argparse
import datetime
import time
from paths_checker import paths_checker

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
    fd.write('\t\t\tThis connectivity matrix indicates the networks that each group \n <ul>\
    <li>can reach with a valid AS-level path (<span class="connectivity-success">&nbsp;&nbsp;&nbsp;</span>); </li>\
    <li>can reach with an invalid AS-level path (<span class="connectivity-invalid">&nbsp;&nbsp;&nbsp;</span>); </li> \
    <li>cannot reach (<span class="connectivity-failure">&nbsp;&nbsp;&nbsp;</span>). </li></ul> \n \
    It takes '+str(int(t))+'s to fully update the matrix. Last upload at '+str(datetime.datetime.now().strftime("%m/%d/%Y, %H:%M:%S"))+'\n')
    fd.write('\t\t</p>\n')
    fd.write('\t\n')
    fd.write('\t\t<div class="progress_container"></div>\n')
    fd.write('\t\n')
    fd.write('\t\t<table class="table table-striped table-bordered">\n')
    fd.write('\t\t\t<thread>\n')
    fd.write('\t\t\t\t<td></td>\n')

    for asn in sorted(as_list):
        if asn < 100:
            fd.write('\t\t\t\t<td style="width: 15px;"> '+" ".join(str(asn))+'</td>\n')
        else:
            fd.write('\t\t\t\t<td style="width: 15px;">'+" ".join(str(asn))+'</td>\n')

    fd.write('\t\t\t</thead>\n')

    for asn_from in sorted(as_list):
        fd.write('\t\t\t<tr>\n')
        fd.write('\t\t\t<td>G'+str(asn_from)+'</td>\n')
        for asn_to in sorted(as_list):
            if co_dic[asn_from][asn_to] == 2:
                fd.write('\t\t\t\t<td class="connectivity-success" title="AS{} <-> AS{}: Reachable with valid path"><span class="glyphicon glyphicon-ok text-success"></td>\n'.format(asn_from, asn_to))
            elif co_dic[asn_from][asn_to] == 1:
                fd.write('\t\t\t\t<td class="connectivity-invalid" title="AS{} <-> AS{}: Reachable with invalid path"><span class="glyphicon glyphicon-ok text-success"></td>\n'.format(asn_from, asn_to))
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
    fd.write('\t\tvar num_reachable_invalid   = $("table").find("td.connectivity-invalid").length;\n')
    fd.write('\t\tvar num_unreachable = $("table").find("td.connectivity-failure").length;\n')
    fd.write('\t\tvar num_total = num_reachable + num_reachable_invalid + num_unreachable;\n')
    fd.write('\t\tvar perc_reachable = num_reachable / num_total * 100;\n')
    fd.write('\t\tvar perc_reachable_invalid = num_reachable_invalid / num_total * 100;\n')
    fd.write('\t\tvar perc_unreachable = num_unreachable / num_total * 100;\n')
    fd.write('\t\t$(".progress_container").html("<div class=\\\"progress\\\"> \
    <div class=\\\"progress-bar progress-bar-success\\\" role=\\\"progressbar\\\" style=\\\"width:"+perc_reachable+"%\\\">Reachable ("+Math.round(perc_reachable)+"%)</div> \
    <div class=\\\"progress-bar progress-bar-warning\\\" role=\\\"progressbar\\\" style=\\\"width:"+perc_reachable_invalid+"%\\\">Reachable invalid path ("+Math.round(perc_reachable_invalid)+"%)</div> \
    <div class=\\\"progress-bar progress-bar-danger\\\" role=\\\"progressbar\\\" style=\\\"width:"+perc_unreachable+"%\\\">Not reachable ("+Math.round(perc_unreachable)+"%)</div></div>");\n')
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

if __name__ == '__main__':

    as_list = []
    
    with open('/tmp/AS_config.txt', 'r') as fd:
        for line in fd.readlines(): 
            linetab = line.rstrip('\n').split('\t')
            asn = int(linetab[0])
            astype = linetab[1]

            if astype == 'AS':
                as_list.append(asn)

    while True:
        paths_checker()

        co_dic = {}
        with open('/tmp/connectivity.txt', 'r') as fd:
            for line in fd.readlines():
                linetab = line.rstrip('\n').split('\t')
                from_as = int(linetab[0])
                to_as = int(linetab[1])
                co = linetab[2]

                if from_as not in co_dic:
                    co_dic[from_as] = {}
                if to_as not in co_dic[from_as]:
                    co_dic[from_as][to_as] = 0

                co_dic[from_as][to_as] = 1 if co == 'True' else 0

        with open('/tmp/path_checks.txt', 'r') as fd:
            for line in fd.readlines():
                linetab = line.rstrip('\n').split('\t')
                from_as = int(linetab[0])
                to_as = int(linetab[1])
                if co_dic[from_as][to_as] == 1:
                    co_dic[from_as][to_as] = 1 if linetab[2] == 'Invalid' else 2
    
        update_matrix(as_list, co_dic, 1)
        time.sleep(10)

