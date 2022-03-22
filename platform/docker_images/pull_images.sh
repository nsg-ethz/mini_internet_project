#!/bin/bash
#
# Pull the latest version of all the docker images used in the mini-Internet

set -o errexit
set -o pipefail
set -o nounset

images=(router ixp host ssh measurement dns switch matrix vpn vlc hostm krill routinator webserver)

# If you want to use your custom docker containers and upload them into
# docker hub, change the docker username with your own docker username.
docker_name=miniinterneteth

for image in "${images[@]}"; do
    echo docker pull "${docker_name}/d_${image}"
    docker pull "${docker_name}/d_${image}"
done