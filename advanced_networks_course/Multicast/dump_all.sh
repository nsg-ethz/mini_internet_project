#!/bin/bash

# Usage ./dump_all.sh [TCPDUMP-FILTER]

set -e

# Wrap filter arguments so we can pass them on.
filter="'$@'"
padding=8  # min length for string display

# AFAIK, there is no elegant way to pass start/stop signals to a background
# docker process. Just the docker exec receives the signal, not the command
# within. So we save the PID of the inner process to kill it manually later.

# Create an id which we use to identify the proccess in the containers
id=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

function pidfile # interface
{
    echo "/var/run/$1-$id.pid"
}

declare ifs=(
    # router:if
    # host ifs.
    "left:host"
    "right:host"
    "top:host"
    "center:host"
    # switch ifs.
    "bottoml:l2"
    "bottomr:l2"
    # inter-router ifs.
    "center:left"
    "center:top"
    "center:right"
    "center:bottomr"
    "center:bottoml"
    "left:top"
    "top:right"
    "right:bottomr"
    "bottomr:bottoml"
    "bottoml:left"
)

function containername  #router
{
    uppercase="$(echo $1 | tr '[:lower:]' '[:upper:]')"
    echo "1_${uppercase}router"
}

function ifname  # router shortname
{
    if [[ $2 == "host" ]]; then
        echo $2
    elif [[ $2 == "l2" ]]; then
        rname="$(echo $1 | tr '[:lower:]' '[:upper:]')"
        echo "$rname-L2"
    else
        uppercase="$(echo $2 | tr '[:lower:]' '[:upper:]')"
        echo "port_$uppercase"
    fi
}


function startdump  # container interface prefix
{
    pid="$(pidfile $2)"
    # The actual command: tcpdump for interface and filters.
    # We need to turn of buffering using stdbuf for continuous output.
    # sed for output formatting.
    cmd="stdbuf -o0 tcpdump -nti $2 $filter 2>/dev/null | sed -ue 's/^/$3/;'"
    # Run in background, save PID to file, and wait for command.
    background="$cmd & echo \$! > $pid && wait"
    # Send to container.
    sudo docker exec -t $1 bash -c "$background"
}

function stopdump # container interface
{
    pid="$(pidfile $2)"
    sudo docker exec -t $1 bash -c "kill \`cat $pid\` && rm $pid"
}


# Start dump for all containers.
function startall
{
    for tuple in ${ifs[@]}; do
        IFS=":" read -a fields <<< "$tuple"
        router=${fields[0]}
        if=${fields[1]}
        container="$(containername $router)"
        interface="$(ifname $router $if)"
        prefix="$(printf %-${padding}s $router) <> $(printf %-${padding}s $if)"
        startdump $container $interface "$prefix" &
    done
    wait
}

# Stop dump for all containers.
function stopall
{
    for tuple in ${ifs[@]}; do
        IFS=":" read -a fields <<< "$tuple"
        router=${fields[0]}
        if=${fields[1]}
        container="$(containername $router)"
        interface="$(ifname $router $if)"
        stopdump $container $interface &
    done
    wait  # we stop all in parallel to reduce waiting time.
}


# Register cleanup.
trap "exit" INT TERM ERR
trap "stopall" EXIT

# Start dump.
if [[ $filter != "''" ]]; then
    echo "Dumping $filter on all links."
else
    echo "Dumping everything on all links."
fi
startall
