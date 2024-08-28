#!/bin/bash

trap 'exit 1' ERR
set -o errexit
set -o pipefail
set -o nounset
#
# Helper file defining a function which simplifies running for-loop cycles in
# parallel.
#
# Example:
#
#   source "${DIRECTORY}"/setup/_parallel_helper.sh
#   for ((k=0;k<5;k++)); do
#     (
#       echo "Task${k}: Starting the task..."
#       sleep 2
#       echo "Task${k}: Task completed!"
#     ) &
#     wait_if_n_tasks_are_running
#   done
#
#   wait

N_CORES=$(grep -c ^processor /proc/cpuinfo)
N_THREADS_PER_CORE=$(lscpu | grep -E '^Thread\(s\) per core:' | awk '{print $4}')
N_TASKS=$((N_CORES * N_THREADS_PER_CORE)) # utilize hyperthreading

# Function to monitor tasks
wait_if_n_tasks_are_running() {
    # Check number of running tasks
    if [[ $(jobs -r -p | wc -l) -ge $N_TASKS ]]; then
        echo "Current number of running tasks exceeds threshold ($N_TASKS). Waiting..."
        wait -n # wait for any one background job to finish
    fi
}
