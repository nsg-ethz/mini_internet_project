# This script is used to configure ASes that were originally not preconfigured (NoConfig flag)
# The Layer2 network is not configured, only the L3 network as well as the hosts

### TO UPDATE ###
# this variable is the absolute path to the platform directory.
PLATFORM_DIR=
# this variable includes all the AS number that need to be configured.
ASN_TO_CONFIGURE=
# this variable contains all the router names that need to be configured.
ROUTER_NAMES=

for group_number in ASN_TO_CONFIGURE
do
    rid=1
    # This loop should iterate over the router, starting from lower ID to higher ID.
    for router_name in ROUTER_NAMES
    do
        chmod 755 $PLATFORM_DIR/groups/g${group_number}/${router_name}/init_rpki_conf.sh
        docker cp $PLATFORM_DIR/groups/g${group_number}/${router_name}/init_full_conf.sh ${group_number}_${router_name}router:/home/
        docker cp $PLATFORM_DIR/groups/g${group_number}/${router_name}/init_rpki_conf.sh ${group_number}_${router_name}router:/home/
        docker exec -it ${group_number}_${router_name}router ./home/init_full_conf.sh
        docker exec -it ${group_number}_${router_name}router ./home/init_rpki_conf.sh

        docker exec -it ${group_number}_${router_name}host ip address add ${group_number}.$((100+$rid)).0.1/24 dev ${router_name}router 
        docker exec -it ${group_number}_${router_name}host ip route add default via ${group_number}.$((100+$rid)).0.2

        rid=$(($rid+1))
        echo $group_number $router_name
    done
done
