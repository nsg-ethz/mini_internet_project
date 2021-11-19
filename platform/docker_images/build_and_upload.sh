#!/bin/bash
#
# build all images and upload to the docker hub

set -o errexit
set -o pipefail
set -o nounset

images=(base base_supervisor host router ixp ssh measurement dns switch matrix vpn vlc hostm routinator krill)

for image in "${images[@]}"; do
    docker build --tag="d_${image}" "docker_images/${image}/"
done

docker login

# If you want to use your custom docker containers and upload them into
# docker hub, change the docker username with your own docker username.
docker_name=temparus

# Upload all images to docker hub except the first two (base images).
for image in "${images[@]:2}"; do
    docker tag "d_${image}" "${docker_name}/d_${image}"
    docker push "${docker_name}/d_${image}"
done
