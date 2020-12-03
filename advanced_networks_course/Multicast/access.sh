#!/bin/bash

if [ $# -lt 1 ]; then
    echo $0: usage: access_cli.sh device_name [command]
    exit 1
fi

# Declare a map of shortcuts for easier access.
# Associative arrays in bash: https://stackoverflow.com/a/3467959
declare -A shortcuts=(
    # Shortcut: container name
    ["left"]="1_LEFTrouter"
    ["top"]="1_TOProuter"
    ["right"]="1_RIGHTrouter"
    ["center"]="1_CENTERrouter"
    ["bottoml"]="1_BOTTOMLrouter"
    ["bottomr"]="1_BOTTOMRrouter"
    ["left-host"]="1_LEFThost"
    ["top-host"]="1_TOPhost"
    ["right-host"]="1_RIGHThost"
    ["center-host"]="1_CENTERhost"
)

lowercase="$(echo $1 | tr '[:upper:]' '[:lower:]')"
container="${shortcuts[$lowercase]}"

# Set default commands
if [[ $container == *"router" ]]; then
    cmd=vtysh
fi
if [[ $container == *"host" ]]; then
    cmd=bash
fi

# Fallback
if [ -z $container ]; then
    echo "\`$1\` is not valid shortcut. Using as container name..."
    echo "(For shortcuts, use \"<router>\" or \"<router>-host\")"
    container=$1
    cmd=bash
fi


# Execute provided or default command.

if [ $# -lt 2 ]; then
    # Use default command
    sudo docker exec -it $container $cmd
    exit 0
fi

# Use provided command instead
sudo docker exec -it $container ${@: 2}
