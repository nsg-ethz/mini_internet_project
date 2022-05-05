import json
import glob
import numpy as np
from PIL import Image   

# Build the image from the matrix data source. 
def make_image(infile, outfile):
    with open(infile, 'r') as fd:
        json_data = json.load(fd)

    # Create a mapping group number -> ID.
    mapping = {}
    for fromg in json_data['connectivity']:
        mapping[int(fromg)] = len(mapping) 

    # Create the RGB matrix
    matrix = np.zeros((len(mapping), len(mapping), 3), dtype=np.uint8)

    # Collect validity and connectivity for every pair of ASes.
    for fromg in json_data['connectivity']:
        for tog, connectivity in json_data['connectivity'][fromg].items():
            
            f = mapping[int(fromg)]
            t = mapping[int(tog)]

            if connectivity:
                try:
                    if json_data['validity'][fromg][tog]:
                        matrix[f][t] = [0,255,0]
                    else:
                        matrix[f][t] = [255,127,0]

                except:
                        matrix[f][t] = [0,255,0]

            elif not connectivity:
                matrix[f][t] = [255,0,0]
            else:
                print (connectivity)
            
    img = Image.fromarray(matrix, 'RGB')
    img = img.resize((800,800))
    img.save(outfile)

# Build the GIF from the set of images.
def gif(indir):
    frames = [Image.open(image) for image in glob.glob(f"{indir}/*.png")]
    frame_one = frames[0]
    frame_one.save(indir+"/matrix.gif", format="GIF", append_images=frames,
        save_all=True, duration=20, loop=0)

# Generate the HTML file (to use in case you prefer to generate the GIF from HTML files)
def generate_html(infile, outfile):

    with open(infile, 'r') as fd:
        json_data = json.load(fd)

        # List with all the ASes
        as_list = json_data['connectivity'].keys()

        # Connectivity dictionnary
        co_dic = dict.fromkeys(as_list)

        # Collect validity and connectivity for every pair of ASes.
        for fromg in json_data['connectivity']:
            co_dic[fromg] = dict.fromkeys(as_list)

            for tog, connectivity in json_data['connectivity'][fromg].items():
                if connectivity:
                    try:
                        if json_data['validity'][fromg][tog]:
                            co_dic[fromg][tog] = 'valid'
                        else:
                            co_dic[fromg][tog] = 'invalid'

                    except:
                            co_dic[fromg][tog] = 'valid'
                    
                elif not connectivity:
                    co_dic[fromg][tog] = 'none'

    fd = open(outfile, 'w')

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
    (<span class="connectivity-failure">&nbsp;&nbsp;&nbsp;</span>)\n')
    fd.write('\t\t</p>\n')
    fd.write('\t\n')
    fd.write('\t\t<div class="progress_container"></div>\n')
    fd.write('\t\n')
    fd.write('\t\t<table class="table table-striped table-bordered">\n')
    fd.write('\t\t\t<thread>\n')
    fd.write('\t\t\t\t<td></td>\n')

    for asn in sorted(as_list):
        if int(asn) < 100:
            fd.write('\t\t\t\t<td style="width: 15px;"> '+" ".join(str(asn))+'</td>\n')
        else:
            fd.write('\t\t\t\t<td style="width: 15px;">'+" ".join(str(asn))+'</td>\n')

    fd.write('\t\t\t</thead>\n')

    for asn_from in sorted(as_list):
        fd.write('\t\t\t<tr>\n')
        fd.write('\t\t\t<td>G'+str(asn_from)+'</td>\n')
        for asn_to in sorted(as_list):
            if co_dic[asn_from][asn_to] == 'valid':
                fd.write('\t\t\t\t<td class="connectivity-success" title="AS{} <-> AS{}: Reachable"><span class="glyphicon glyphicon-ok text-success"></td>\n'.format(asn_from, asn_to))
            elif co_dic[asn_from][asn_to] == 'invalid':
                fd.write('\t\t\t\t<td class="connectivity-invalid" title="AS{} <-> AS{}: Reachable with invalid path"><span class="glyphicon glyphicon-ok text-success"></td>\n'.format(asn_from, asn_to))
            else:
                fd.write('\t\t\t\t<td class="connectivity-failure" title="AS{} <-> AS{}: Not Reachable"><span class="glyphicon glyphicon-remove text-danger"></td>\n'.format(asn_from, asn_to))
        fd.write('\t\t\t</tr>\n')

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

    fd.close()