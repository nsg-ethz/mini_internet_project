#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "Pass the video name (a file in /home/videos/) as argument."
    exit 1
fi

cur_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
file="$cur_dir/$1"

if [ -f $file ]; then
runuser vlc -c  "vlc -vvv $file --sout '#rtp{access=udp,mux=ts,dst=237.0.0.10,port=1234,sap,group=\"Video\",name=Multicast,ttl=10}' :sout-all --loop"
else
    echo "$file does not exist!"
fi