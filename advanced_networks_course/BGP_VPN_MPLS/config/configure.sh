#!/bin/bash

for c in 1_R1router:R1.sh \
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

    echo "Configuring "$cname" ..."

    sudo docker cp config/$cscript $cname:/home/
    sudo docker exec -it $cname chmod 755 /home/$cscript
    sudo docker exec -it $cname /home/$cscript
done
