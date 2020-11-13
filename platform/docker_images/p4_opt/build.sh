#!/bin/bash
#
# build all images and upload to the docker hub

set -o errexit
set -o pipefail
set -o nounset

docker build --tag=d_p4_opt docker_images/p4_opt/

docker login
docker_name=thomahol

container_name=d_p4_opt
docker tag "${container_name}" "${docker_name}"/"${container_name}"
docker push "${docker_name}"/"${container_name}"
