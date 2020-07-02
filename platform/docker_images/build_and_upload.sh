#!/bin/bash
#
# build all images and upload to the docker hub

set -o errexit
set -o pipefail
set -o nounset

docker build --tag=d_router docker_images/router/
docker build --tag=d_ixp docker_images/ixp/
docker build --tag=d_host docker_images/host/
docker build --tag=d_ssh docker_images/ssh/
docker build --tag=d_measurement docker_images/measurement/
docker build --tag=d_dns docker_images/dns/
docker build --tag=d_switch docker_images/switch/
docker build --tag=d_matrix docker_images/matrix/
docker build --tag=d_vpn docker_images/vpn/
docker build --tag=d_vlc docker_images/vlc/
docker build --tag=d_hostm docker_images/hostm/


docker login

# If you want to use your custom docker containers and upload them into
# docker hub, change the docker username with your own docker username.
docker_name=thomahol

container_name=d_router
docker tag "${container_name}" "${docker_name}"/"${container_name}"
docker push "${docker_name}"/"${container_name}"

container_name=d_ixp
docker tag "${container_name}" "${docker_name}"/"${container_name}"
docker push "${docker_name}"/"${container_name}"

container_name=d_host
docker tag "${container_name}" "${docker_name}"/"${container_name}"
docker push "${docker_name}"/"${container_name}"

container_name=d_ssh
docker tag "${container_name}" "${docker_name}"/"${container_name}"
docker push "${docker_name}"/"${container_name}"

container_name=d_measurement
docker tag "${container_name}" "${docker_name}"/"${container_name}"
docker push "${docker_name}"/"${container_name}"

container_name=d_dns
docker tag "${container_name}" "${docker_name}"/"${container_name}"
docker push "${docker_name}"/"${container_name}"

container_name=d_switch
docker tag "${container_name}" "${docker_name}"/"${container_name}"
docker push "${docker_name}"/"${container_name}"

container_name=d_matrix
docker tag "${container_name}" "${docker_name}"/"${container_name}"
docker push "${docker_name}"/"${container_name}"

container_name=d_vpn
docker tag "${container_name}" "${docker_name}"/"${container_name}"
docker push "${docker_name}"/"${container_name}"

container_name=d_vlc
docker tag "${container_name}" "${docker_name}"/"${container_name}"
docker push "${docker_name}"/"${container_name}"

container_name=d_hostm
docker tag "${container_name}" "${docker_name}"/"${container_name}"
docker push "${docker_name}"/"${container_name}"
