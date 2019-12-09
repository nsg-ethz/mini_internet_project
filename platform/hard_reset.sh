#!/bin/bash
#
# remove all container, bridges and temporary files

# kill all container
for container in `docker ps -q`; do
  docker kill "${container}" >/dev/nul &
done
wait

# remove all container & restart docker
docker system prune -f
service docker restart

# remove all ovs-bridges
if [ "$(ovs-vsctl list-br | wc -l )" != "0" ];then
  echo -n "ovs-vsctl " > tmp.txt

  for bridge in $(ovs-vsctl list-br); do
    echo -n "-- del-br ""${bridge}"" " >> tmp.txt
  done

  bash  < tmp.txt
  rm -f tmp.txt
fi

# Delete virtual interfaces
for n in $(ip -o link show | awk -F': ' '{print $2}'); do
    if [[ ! $n =~ ^(en|lo|eth) ]]; then
        ip link delete $(echo $n | cut -d'@' -f 1)
    fi
done

# delete old running config files
if [ -e groups ]; then
  rm -rf groups
fi

# Kill the openvpn processes
for pid in $(ps aux | grep vpn | awk '{print $2}'); do
    kill -9 $pid 2>&1 >/dev/null
done
