#!/bin/bash

set -e

command=/usr/lib/frr/frrinit.sh
pid_dir="${FRR_PID_DIR:-/var/run/frr}"
wait_helper="${WAIT_HELPER:-/usr/local/bin/wait-piddfs.py}"

monitor_pid=""

function stop() {
    trap - SIGINT SIGTERM

    if [ -n "${monitor_pid:-}" ]; then
        kill "$monitor_pid" 2>/dev/null || true
        wait "$monitor_pid" 2>/dev/null || true
    fi

    $command stop
    exit 0
}

function reload() {
    $command reload
}

trap "stop" SIGINT SIGTERM
trap "reload" SIGHUP

# Launch frr daemons
$command start
sleep 2

# Validate initial state once.
# This preserves the old behavior that startup fails if any daemon is not alive.
if ! $command status > /dev/null; then
    $command status
    exit 1
fi

# Block until any currently-running FRR daemon exits.
python3 "$wait_helper" "$pid_dir" &
monitor_pid=$!

if wait "$monitor_pid"; then
    # The helper should not normally exit 0.
    $command status
    exit 1
else
    rc=$?

    # rc=1 means one daemon exited, or was already gone.
    if [ "$rc" -eq 1 ]; then
        $command status
        exit 1
    fi

    # rc=2 means unsupported platform / permission / helper setup error.
    exit "$rc"
fi