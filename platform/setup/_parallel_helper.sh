#!/bin/bash
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

# Set N_TASKS to the number of processor cores
# (twice as much if CPU has hyperthreading)
N_TASKS=$(grep -c ^processor /proc/cpuinfo)

function wait_if_n_tasks_are_running {
    # allow to execute up to N_TASKS jobs in parallel
    if [[ $(jobs -r -p | wc -l) -ge $N_TASKS ]]; then
        # If N_TASKS are running, wair for the next task to terminate.
        wait -n
    fi
}
