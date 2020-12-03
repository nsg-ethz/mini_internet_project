#!/bin/bash

# Get the current script directory, no matter where we are called from.
# https://stackoverflow.com/questions/59895/how-to-get-the-source-directory-of-a-bash-script-from-within-the-script-itself
cur_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
mkdir $cur_dir/saved_configs

for c in \
1_R1router:R1.sh \
1_R2router:R2.sh \
1_R3router:R3.sh \
1_R4router:R4.sh \
1_R5router:R5.sh \
20_CENT1router:CENT1.sh \
20_CENT2router:CENT2.sh \
30_S1router:S1.sh
do
    cname=$(echo $c | cut -f 1 -d ':')
    cscript=$(echo $c | cut -f 2 -d ':')
    rname=$(echo $cscript | cut -f 1 -d '')

    echo "Configuring "$cname" ..."

    sudo docker exec -it $cname vtysh -c "write"
    sudo docker cp $cname:/etc/frr/frr.conf $cur_dir/saved_configs/$rname
    sudo chown $USER $cur_dir/saved_configs/$rname
done
