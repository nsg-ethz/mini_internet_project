#!/bin/bash

while true
do
    python3 lgparse.py ../../groups/
    python3 lganalyze.py print-html > analysis.html

    scp analysis.html thomahol@virt07.ethz.ch:/home/web_commnet/public_html/routing_project/bgp_analyzer/
    echo 'html file sent'
    sleep 120
done
