# This script is used to configure an ASes that was originally not pre-configure (NoConfig)
# The Layer2 network is not configured, only the L3 network as well as the hosts

for group_number in 12 31 32 51 52 109 110
do
    rid=1
    for router_name in LOND ZURI PARI GENE NEWY BOST ATLA MIAM
    do
        docker cp groups/g${group_number}/${router_name}/init_full_conf.sh ${group_number}_${router_name}router:/home/
        docker exec -it ${group_number}_${router_name}router ./home/init_full_conf.sh

        docker exec -it ${group_number}_${router_name}host ifconfig ${router_name}router ${group_number}.$((100+$rid)).0.1/24
        docker exec -it ${group_number}_${router_name}host ip route add default via ${group_number}.$((100+$rid)).0.2

        rid=$(($rid+1))
    done
done
