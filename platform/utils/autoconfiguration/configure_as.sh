# This script is used to configure ASes that were originally not preconfigured (NoConfig flag)
# The Layer2 network is not configured, only the L3 network as well as the hosts

### TO UPDATE ###
# this variable is the absolute path to the platform directory.
PLATFORM_DIR=/home/alex/mini_internet_project/platform
# this variable includes all the AS number that need to be configured.
ASN_TO_CONFIGURE="89 109"
# this variable contains all the router names that need to be configured.
# The order is important, as it will be used to assign IP addresses to the routers.
ROUTER_NAMES="CAIR KHAR ADDI NAIR CAPE LUAN KINS ACCR"
CONFIG_FILES="conf_init.sh conf_full.sh conf_rpki.sh"

echo "Updating configs."
echo "You can ignore 'route-map' does not exist error (it will be defined)"
echo "You can ignore 'clear ip ospf process' message (the script does that)"

for group_number in $ASN_TO_CONFIGURE
do
    rid=1
    # This loop should iterate over the router, starting from lower ID to higher ID.
    for router_name in $ROUTER_NAMES
    do
        echo "$group_number $router_name: Configuring"
        config_dir="$PLATFORM_DIR/groups/g${group_number}/${router_name}/config"
        for config_file in $CONFIG_FILES ; do
            config_file_full="${config_dir}/${config_file}"
            chmod 755 "${config_file_full}"
            docker cp "${config_file_full}" "${group_number}_${router_name}router":"/home/${config_file}" > /dev/null
            docker exec -it "${group_number}_${router_name}router" "./home/${config_file}"
        done

        docker exec -it ${group_number}_${router_name}host ip address add ${group_number}.$((100+$rid)).0.1/24 dev ${router_name}router
        docker exec -it ${group_number}_${router_name}host ip route add default via ${group_number}.$((100+$rid)).0.2


        echo "$group_number $router_name: Clearing BGP and OSPF"
        docker exec -it "${group_number}_${router_name}router" vtysh -c 'clear ip bgp *' -c 'clear ip ospf process'


        rid=$(($rid+1))
    done
done
