#!/bin/bash

if [ $# -lt 1 ]; then
    echo $0: usage: access_cli.sh device_name [command]
    exit 1
fi

case $1 in
    "R1")
        DEV=1_R1router
        CMD=vtysh
        ;;
    "R2")
        DEV=1_R2router
        CMD=vtysh
        ;;
    "R3")
        DEV=1_R3router
        CMD=vtysh
        ;;
    "R4")
        DEV=1_R4router
        CMD=vtysh
        ;;
    "R5")
        DEV=1_R5router
        CMD=vtysh
        ;;
    "CENT1")
        DEV=20_CENT1router
        CMD=vtysh
        ;;
    "CENT2")
        DEV=20_CENT2router
        CMD=vtysh
        ;;
    "S1")
        DEV=30_S1router
        CMD=vtysh
        ;;
    "OERL-host")
        DEV=1_L2_CS1_oerl_host
        CMD=bash
        ;;
    "BAHN-host")
        DEV=1_L2_UBS2_bahn_host
        CMD=bash
        ;;
    "PARA-host")
        DEV=1_L2_CS2_para_host
        CMD=bash
        ;;
    "BELLE-host")
        DEV=1_L2_UBS1_belle_host
        CMD=bash
        ;;
    "CENT1-host")
        DEV=20_CENT1host
        CMD=bash
        ;;
    "CENT2-host")
        DEV=20_CENT2host
        CMD=bash
        ;;
    "S1-host")
        DEV=30_S1host
        CMD=bash
        ;;
    *)
        echo "Unknown device name. The available devices are the following:
        R1 R2 R3 R4 CENT1 CENT2 S1 OERL-host BAHN-host PARA-host BELLE-host CENT1-host CENT2-host S1-host"
        exit 1
        ;;
esac

if [ $# -lt 2 ]; then
    # Use default command
    sudo docker exec -it $DEV $CMD
    exit 0
fi

# Use provided command instead
sudo docker exec -it $DEV ${@: 2}
