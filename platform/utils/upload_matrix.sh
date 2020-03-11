#!/bin/bash

while true
do
    docker cp MATRIX:/home/matrix.html matrix.html
    scp matrix.html thomahol@virt07.ethz.ch:/home/web_commnet/public_html/routing_project/matrix/
    echo 'matrix sent'
    sleep 10
done
