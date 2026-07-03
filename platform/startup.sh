#!/bin/bash
#
# starts whole network

# set -x
set -o errexit # exit on error
set -o pipefail # catch errors in pipelines
set -o nounset # exit on undeclared variable

# Check for programs we'll need.
search_path () {
    # display the path to the command
    type -p "$1" > /dev/null && return 0
    echo >&2 "$0: $1 not found in \$PATH, please install and try again"
    exit 1
}

if (($UID != 0)); then
    echo "$0 needs to be run as root"
    exit 1
fi

search_path ovs-vsctl
search_path docker
search_path uuidgen


# # netns: used to create isolated network environments/namespaces
if (ip netns) > /dev/null 2>&1; then :; else
    echo >&2 "${0##*/}: ip utility not found (or it does not support netns),"\
             "cannot proceed"
    exit 1
fi

# # TODO: check the directory is platform/
DIRECTORY=$(cd `dirname $0` && pwd)

echo "$(date +%Y-%m-%d_%H-%M-%S)"

python3 -c "import sys; assert sys.version_info >= (3, 12), 'Python Version is too old!';"

# used to create and activate the python venv
python3 -m venv .env
source .env/bin/activate && pip install -r ./requirements.txt


echo "cleanup.sh"
# add --hard_reset if you want to do a reset
time ./cleanup/cleanup.sh "${DIRECTORY}" 

time python3 ./startup.py -c "${DIRECTORY}/config"

