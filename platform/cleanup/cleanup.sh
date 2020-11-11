#!/bin/bash
#
# remove all container, bridges and temporary files
# will only remove the containers, bridges defined in ../config/

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"

# kill all container
./cleanup/container_cleanup.sh "${DIRECTORY}"

# remove all container & restart docker
docker system prune -f

# remove all OvS switches
echo -n "ovs-vsctl " > ovs_command.txt
./cleanup/host_links_cleanup.sh "${DIRECTORY}"
./cleanup/layer2_cleanup.sh "${DIRECTORY}"
./cleanup/internal_links_cleanup.sh "${DIRECTORY}"
./cleanup/external_links_cleanup.sh "${DIRECTORY}"
./cleanup/measurement_cleanup.sh "${DIRECTORY}"
./cleanup/matrix_cleanup.sh "${DIRECTORY}"
./cleanup/dns_cleanup.sh "${DIRECTORY}"
./cleanup/ssh_cleanup.sh "${DIRECTORY}"
./cleanup/vpn_cleanup.sh "${DIRECTORY}"

bash  < ovs_command.txt || true
rm -f ovs_command.txt

# remove remaining veth pairs (if file available)
if [ -f groups/delete_veth_pairs.sh ]; then
    ./groups/delete_veth_pairs.sh || true
fi

# delete old running config files
if [ -e groups ]; then
  rm -rf groups
fi
