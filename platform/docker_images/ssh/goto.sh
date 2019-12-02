#!/bin/bash

readarray routers < ./router_config.txt
n_routers=${#routers[@]}
n_group=$(cat ./group_number.txt)
location=$1
device=$2


ip=0.0.0.0


for ((i=0;i<n_routers;i++)); do
	router_i=(${routers[$i]})
        rname="${router_i[0]}"

	if [ $location == $rname ] && [ $device == "host" ]; then
		ip=158."$n_group".0."$(($((i+1))*10 +1 ))"
		ssh -o "StrictHostKeyChecking no" root@"$ip"
	elif [ $location == $rname ] && [ $device == "router" ]; then
		ip=158."$n_group".0."$(($((i+1))*10 ))"
		ssh -o "StrictHostKeyChecking no" root@"$ip" vtysh
	fi	
done

if [ $ip == 0.0.0.0 ]; then 
	echo "invalid arguments"
	echo "valid examples:"
        echo "./goto $rname router"
	echo "./goto $rname host"	
	exit
fi
