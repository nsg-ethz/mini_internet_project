#!/bin/bash

# This script pushes in a git repositery the config files of all the routers
# as well as the matrix images and the gif.

# location of the git directory.
USERNAME=thomas
PLATFORM_DIR=/home/thomas/mini_internet_project/platform/
GITADDR=git@gitlab.ethz.ch:nsg/lectures/lec_commnet/projects/2022/routing_project/configs_and_matrix_history_2
GITDIR=/home/thomas/configs_and_matrix_history
rm -rf $GITDIR

# Clone the git repository
sudo -H -u $USERNAME git clone $GITADDR $GITDIR

# Create the dir where to store matrix data.
sudo -H -u $USERNAME mkdir $GITDIR/matrix/
sudo -H -u $USERNAME mkdir $GITDIR/images/

# Copy the css file in the matrix directory and push it
sudo -H -u $USERNAME cp -r css $GITDIR/images/css
sudo -H -u $USERNAME git -C $GITDIR add $GITDIR/images/css

# This function copies the routers config in the git repo.
# It takes as parameters the group number and the config file used for the routers
copy_config () {
    group_number=$1
    group_router_config=$2

    readarray routers < $PLATFORM_DIR/config/$group_router_config
    n_routers=${#routers[@]}

    # Create the directory dedicated to this group in the git repo if not done yet.
    if [[ ! -d "$GITDIR/g$group_number" ]]
    then
        sudo -H -u $USERNAME mkdir $GITDIR/g$group_number
    fi

    # For every router, copy the FRR config in the git repo and change the owner and commit.
    for ((i=0;i<n_routers;i++)); do
        router_i=(${routers[$i]})
        rname="${router_i[0]}"

        cp $PLATFORM_DIR/groups/g$group_number/$rname/frr.conf $GITDIR/g$group_number/$rname.txt
        chown $USERNAME:$USERNAME $GITDIR/g$group_number/$rname.txt
        sudo -H -u $USERNAME git -C $GITDIR add g$group_number/$rname.txt
    done
}

while true
do
    # read mini-Internet configs.
    readarray groups < $PLATFORM_DIR/config/AS_config.txt
    group_numbers=${#groups[@]}

    # Copy routers config for every group.
    for ((k=0;k<group_numbers;k++)); do
        group_k=(${groups[$k]})
        group_number="${group_k[0]}"
        group_as="${group_k[1]}"
        group_config="${group_k[2]}"
        group_router_config="${group_k[3]}"

        if [ "${group_as}" != "IXP" ];then
            echo copy_config $group_number $group_router_config
            copy_config $group_number $group_router_config
        fi
    done

    # Copy matrix source.
    d=$(date +'%m_%d_%Y-%Hh%Mm%Ss')
    wget -O $GITDIR/matrix/matrix_source_$d.json https://duvel.ethz.ch/matrix?raw 
    chown $USERNAME:$USERNAME $GITDIR/matrix/matrix_source_$d.json
    sudo -H -u $USERNAME git -C $GITDIR add $GITDIR/matrix/matrix_source_$d.json

    # Generate the matrix image.
    python3 -c "from make_gif import make_image; make_image('$GITDIR/matrix/matrix_source_$d.json', '$GITDIR/images/$d.png')"
    sudo -H -u $USERNAME git -C $GITDIR add $GITDIR/images/$d.png

    # Generate the matrix GIF.
    python3 -c "from make_gif import gif; gif('$GITDIR/images')"
    sudo -H -u $USERNAME git -C $GITDIR add $GITDIR/images/matrix.gif

    # Generate the matrix HTML file
    python3 -c "from make_gif import generate_html; generate_html('$GITDIR/matrix/matrix_source_$d.json', '$GITDIR/images/$d.html')"
    sudo -H -u $USERNAME git -C $GITDIR add $GITDIR/images/$d.html

    # Commit and push.
    sudo -H -u thomas git -C $GITDIR commit -m "Config $d"
    sudo -H -u thomas git -C $GITDIR push

    sleep 600
done