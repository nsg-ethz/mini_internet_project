#!/bin/bash

if [ $# -ne 2 ]; then
    echo $0: usage ./launch_traceroute.sh src_grp dst_ip
    exit 1
fi

src_grp=$1
dst_ip=$2

readarray mac_address < ./mac_addresses

mac_i="${mac_address[$src_grp]%?}"

for hop in `seq 30`
do
    echo -e 'Hop '$hop':  \c'
    nping --dest-mac "${mac_i}" --interface group_"${src_grp}" --source-ip "${src_grp}".0.199.2 --dest-ip "${dst_ip}" --tr --ttl "${hop}" -c 1 -H --delay 100ms 2> /dev/null | grep RCVD | cut -f 4,7,8,9 -d ' ' | cut -f 2 -d '['
done

