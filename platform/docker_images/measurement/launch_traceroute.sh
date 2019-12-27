#!/bin/bash

if [ $# -ne 2 ]; then
    echo $0: usage ./launch_traceroute.sh src_grp dst_ip
    exit 1
fi

src_grp=$1
dst_ip=$2

for hop in `seq 30`
do
    if [ $src_grp -lt 10 ];then
        dst_mac="aa:22:22:22:22:0"$src_grp
    else
        dst_mac="aa:22:22:22:22:"$src_grp
    fi

    echo -e 'Hop '$hop':  \c'
    nping --dest-mac $dst_mac --interface group_"${src_grp}" --source-ip "${src_grp}".0.199.2 --dest-ip "${dst_ip}" --tr --ttl "${hop}" -c 1 -H --delay 100ms 2> /dev/null | grep RCVD | cut -f 4,7,8,9 -d ' ' | cut -f 2 -d '['
done
