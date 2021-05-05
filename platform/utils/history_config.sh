#!/bin/bash

gitdir=/home/thomas/configs_and_matrix_history
rm -rf $gitdir

sudo -H -u thomas git clone git@gitlab.ethz.ch:nsg/lectures/lec_commnet/projects/2021/routing_project/configs_and_matrix_history.git $gitdir

while true
do
    for ((group=3;group<=10;group++)); do
        if [[ ! -d "$gitdir/g$group" ]]
        then
           sudo -H -u thomas mkdir $gitdir/g$group
        fi

        for r in BROO NEWY CHAR PITT DETR CHIC STLO NASH; do
            cp /home/thomas/mini_internet_project/platform/groups/g$group/$r/frr.conf $gitdir/g$group/$r.txt
            chown thomas:thomas $gitdir/g$group/$r.txt
            sudo -H -u thomas git -C $gitdir add g$group/$r.txt
        done
    done

    for ((group=23;group<=30;group++)); do
        if [[ ! -d "$gitdir/g$group" ]]
        then
            sudo -H -u thomas mkdir $gitdir/g$group
        fi

        for r in BROO NEWY CHAR PITT DETR CHIC STLO NASH; do
            cp /home/thomas/mini_internet_project/platform/groups/g$group/$r/frr.conf $gitdir/g$group/$r.txt
            chown thomas:thomas $gitdir/g$group/$r.txt
            sudo -H -u thomas git -C $gitdir add g$group/$r.txt
        done
    done

    for ((group=43;group<=50;group++)); do
        if [[ ! -d "$gitdir/g$group" ]]
        then
            sudo -H -u thomas mkdir $gitdir/g$group
        fi

        for r in BROO NEWY CHAR PITT DETR CHIC STLO NASH; do
            cp /home/thomas/mini_internet_project/platform/groups/g$group/$r/frr.conf $gitdir/g$group/$r.txt
            chown thomas:thomas $gitdir/g$group/$r.txt
            sudo -H -u thomas git -C $gitdir add g$group/$r.txt
        done
    done

    for ((group=63;group<=70;group++)); do
        if [[ ! -d "$gitdir/g$group" ]]
        then
            sudo -H -u thomas mkdir $gitdir/g$group
        fi

        for r in BROO NEWY CHAR PITT DETR CHIC STLO NASH; do
            cp /home/thomas/mini_internet_project/platform/groups/g$group/$r/frr.conf $gitdir/g$group/$r.txt
            chown thomas:thomas $gitdir/g$group/$r.txt
            sudo -H -u thomas git -C $gitdir add g$group/$r.txt
        done
    done

    for ((group=83;group<=90;group++)); do
        if [[ ! -d "$gitdir/g$group" ]]
        then
            sudo -H -u thomas mkdir $gitdir/g$group
        fi

        for r in BROO NEWY CHAR PITT DETR CHIC STLO NASH; do
            cp /home/thomas/mini_internet_project/platform/groups/g$group/$r/frr.conf $gitdir/g$group/$r.txt
            chown thomas:thomas $gitdir/g$group/$r.txt
            sudo -H -u thomas git -C $gitdir add g$group/$r.txt
        done
    done

    for ((group=103;group<=110;group++)); do
        if [[ ! -d "$gitdir/g$group" ]]
        then
            mkdir $gitdir/g$group
        fi

        for r in BROO NEWY CHAR PITT DETR CHIC STLO NASH; do
            cp /home/thomas/mini_internet_project/platform/groups/g$group/$r/frr.conf $gitdir/g$group/$r.txt
            chown thomas:thomas $gitdir/g$group/$r.txt
            sudo -H -u thomas git -C $gitdir add g$group/$r.txt
        done
    done

    # Save the matrix
    sudo sed '/fully/d' /home/thomas/mini_internet_project/platform/utils/matrix.html > /home/thomas/mini_internet_project/platform/utils/tmp.html
    cp /home/thomas/mini_internet_project/platform/utils/tmp.html $gitdir/matrix.html
    sudo -H -u thomas git -C $gitdir add $gitdir/matrix.html

    d=$(date +'%m/%d/%Y-%Hh%Mm%Ss')
    sudo -H -u thomas git -C $gitdir commit -m "Config $d"
    sudo -H -u thomas git -C $gitdir push

    sleep 300
done