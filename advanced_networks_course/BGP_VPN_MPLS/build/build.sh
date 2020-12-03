#!/bin/bash

# Get the current script directory, no matter where we are called from.
# https://stackoverflow.com/questions/59895/how-to-get-the-source-directory-of-a-bash-script-from-within-the-script-itself
cur_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
platform_dir=$HOME/mini_internet_project/platform/

# Pull the latest version of the platform
echo "Pull the mini-Internet repository"
git -C $platform_dir pull

# Building the topology
echo "Copy the configuration files"
cp -r $cur_dir/topo/* $platform_dir/config/

echo "Clean-up the mini-Internet currently running (if any)"
(cd $platform_dir; sudo $platform_dir/cleanup/hard_reset.sh)
echo "Run the new mini-Internet"
(cd $platform_dir; sudo $platform_dir/startup.sh)

# Run the default configuration
for c in \
1_R1router:R1.sh \
1_R2router:R2.sh \
1_R3router:R3.sh \
1_R4router:R4.sh \
1_R5router:R5.sh \
20_CENT1router:CENT1.sh \
20_CENT2router:CENT2.sh \
30_S1router:S1.sh \
20_CENT1host:CENT1-host.sh \
20_CENT2host:CENT2-host.sh \
30_S1host:S1-host.sh \
1_L2_UBS1_belle_host:BELLE-host.sh \
1_L2_UBS2_bahn_host:BAHN-host.sh \
1_L2_CS1_oerl_host:OERL-host.sh \
1_L2_CS2_para_host:PARA-host.sh \
1_R5host:R5-host.sh
do
    cname=$(echo $c | cut -f 1 -d ':')
    cscript=$(echo $c | cut -f 2 -d ':')

    echo "Configuring $cname using $cscript..."
    sudo docker cp $cur_dir/default_config/$cscript $cname:/home/
    sudo docker exec -it $cname chmod 755 /home/$cscript
    sudo docker exec -it $cname /home/$cscript
done
