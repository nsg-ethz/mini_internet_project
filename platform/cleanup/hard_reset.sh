#!/bin/bash
#
# remove all container, bridges, network namespaces, and temporary files

# Remove all containers
docker rm -f $(docker ps -q) 2>/dev/null || echo "No containers to remove".

# Remove _everything_ from the Open vSwitch.
ovs-vsctl emer-reset

# Delete virtual interfaces except for known system interfaces.
for n in $(ip -o link show | awk -F': ' '{print $2}'); do
    if [[ ! $n =~ ^(en|lo|eth|docker0|virbr0) ]]; then
        ip link delete $(echo $n | cut -d'@' -f 1)
    fi
done

# Delete all network namespaces
ip -all netns delete

# delete old running config files
if [ -e groups ]; then
  rm -rf groups
fi

# Kill the openvpn processes
for pid in $(ps aux | grep vpn | awk '{print $2}'); do
    kill -9 $pid 2>&1 >/dev/null
done

# Clean up and restart docker.
docker system prune -f -v
service docker restart
