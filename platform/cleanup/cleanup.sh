#!/bin/bash
#
# remove all container, bridges and temporary files
# will only remove the containers, bridges defined in ../config/

# set -x
set -o errexit
set -o pipefail
set -o nounset

if [ "$#" == 0 ]; then
  echo "usage: ${0##*/} directory" 2>&1
  exit 1
fi

# root privilege check in case this script is directly executed
if (($UID != 0)); then
    echo "$0 needs to be run as root"
    exit 1
fi

DIRECTORY="$1"
cd $DIRECTORY

python3 -m venv .env
source .env/bin/activate && pip install -r ./requirements.txt

cd ..
if [[ $* == *--hard_reset* ]] then
  python3 -m platform.cleanup.cleanup -c "$(pwd)/platform/config" --hard_reset
else
  python3 -m platform.cleanup.cleanup -c "$(pwd)/platform/config"
fi
