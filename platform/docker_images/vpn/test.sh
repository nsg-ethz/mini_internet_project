# Run the VPN container
sudo docker run --net='none' -itd --name="vpn" --privileged thomahol/d_vpn

# Run h1 and h2
sudo docker run --net='none' -itd --name="h1" --privileged thomahol/d_vpn
sudo docker run --net='none' -itd --name="h2" --privileged thomahol/d_vpn

# Te remove
sudo ovs-vsctl del-br "s1"
sudo ovs-vsctl del-br "s2"


veth_switch_name="s1h1_l"
veth_host_name="h1s1_l"
ovs_name="s1"
container_name="h1"
sudo ip link del $veth_switch_name type veth peer name $veth_host_name
sudo ovs-vsctl add-br $ovs_name
sudo ip link add $veth_switch_name type veth peer name $veth_host_name
sudo ovs-vsctl -- add-port $ovs_name $veth_switch_name -- set interface $veth_switch_name external_ids:container_id=$container_name external_ids:container_iface=$veth_host_name
sudo ip link set $veth_switch_name up
PID=$(sudo docker inspect -f '{{.State.Pid}}' $container_name)
sudo ip link set $veth_host_name netns $PID



veth_switch_name="s1vpn_l"
veth_host_name="vpns1_l"
ovs_name="s1"
container_name="vpn"
sudo ip link del $veth_switch_name type veth peer name $veth_host_name
sudo ovs-vsctl add-br $ovs_name
sudo ip link add $veth_switch_name type veth peer name $veth_host_name
sudo ovs-vsctl -- add-port $ovs_name $veth_switch_name -- set interface $veth_switch_name external_ids:container_id=$container_name external_ids:container_iface=$veth_host_name
sudo ip link set $veth_switch_name up
PID=$(sudo docker inspect -f '{{.State.Pid}}' $container_name)
sudo ip link set $veth_host_name netns $PID


veth_switch_name="s2h2_l"
veth_host_name="h2s2_l"
ovs_name="s2"
container_name="h2"
sudo ip link del $veth_switch_name type veth peer name $veth_host_name
sudo ovs-vsctl add-br $ovs_name
sudo ip link add $veth_switch_name type veth peer name $veth_host_name
sudo ovs-vsctl -- add-port $ovs_name $veth_switch_name -- set interface $veth_switch_name external_ids:container_id=$container_name external_ids:container_iface=$veth_host_name
sudo ip link set $veth_switch_name up
PID=$(sudo docker inspect -f '{{.State.Pid}}' $container_name)
sudo ip link set $veth_host_name netns $PID

veth_switch_name="s2vpn_l"
veth_host_name="vpns2_l"
ovs_name="s2"
container_name="vpn"
sudo ip link del $veth_switch_name type veth peer name $veth_host_name
sudo ovs-vsctl add-br $ovs_name
sudo ip link add $veth_switch_name type veth peer name $veth_host_name
sudo ovs-vsctl -- add-port $ovs_name $veth_switch_name -- set interface $veth_switch_name external_ids:container_id=$container_name external_ids:container_iface=$veth_host_name
sudo ip link set $veth_switch_name up
PID=$(sudo docker inspect -f '{{.State.Pid}}' $container_name)
sudo ip link set $veth_host_name netns $PID


# Setup the bridhe got openvpn

#!/bin/bash

#################################
# Set up Ethernet bridge on Linux
# Requires: bridge-utils
#################################

# Define Bridge Interface
br="br0"

# Define list of TAP interfaces to be bridged,
# for example tap="tap0 tap1 tap2".
tap="tap0"

# Define physical ethernet interface to be bridged
# with TAP interface(s) above.
eth="vpns1_l"
eth_ip="1.0.0.2"
eth_netmask="255.255.255.0"
eth_broadcast="1.0.0.255"

for t in $tap; do
    openvpn --mktun --dev $t
done

brctl addbr $br
brctl addif $br $eth

for t in $tap; do
    brctl addif $br $t
done

for t in $tap; do
    ifconfig $t 0.0.0.0 promisc up
done

ifconfig $eth 0.0.0.0 promisc up

ifconfig $br $eth_ip netmask $eth_netmask broadcast $eth_broadcast

####

sudo docker run --net='none' -itd --name="vpn_client" --privileged thomahol/d_vpn

veth_switch_name="ovs_client"
veth_host_name="client_ovs"
ovs_name="ovs_vpn"
container_name="vpn_client"
sudo ip link del $veth_switch_name type veth peer name $veth_host_name
sudo ovs-vsctl add-br $ovs_name
sudo ip link add $veth_switch_name type veth peer name $veth_host_name
sudo ovs-vsctl -- add-port $ovs_name $veth_switch_name -- set interface $veth_switch_name external_ids:container_id=$container_name external_ids:container_iface=$veth_host_name
sudo ip link set $veth_switch_name up
PID=$(sudo docker inspect -f '{{.State.Pid}}' $container_name)
sudo ip link set $veth_host_name netns $PID

veth_switch_name="ovs_l2vpn"
veth_host_name="l2vpn_ovs"
ovs_name="ovs_vpn"
container_name="1_ZURI_L2_vpn_1"
sudo ip link del $veth_switch_name type veth peer name $veth_host_name
sudo ovs-vsctl add-br $ovs_name
sudo ip link add $veth_switch_name type veth peer name $veth_host_name
sudo ovs-vsctl -- add-port $ovs_name $veth_switch_name -- set interface $veth_switch_name external_ids:container_id=$container_name external_ids:container_iface=$veth_host_name
sudo ip link set $veth_switch_name up
PID=$(sudo docker inspect -f '{{.State.Pid}}' $container_name)
sudo ip link set $veth_host_name netns $PID


sudo ovs-vsctl del-br vpnbr1
sudo ip link del vpn_1 type veth peer name g1_vpn_1

sudo ip link add vpn_1 type veth peer name g1_vpn_1
sudo ovs-vsctl add-br vpnbr1
sudo ovs-vsctl add-port vpnbr1 tap_g1
sudo ovs-vsctl add-port vpnbr1 g1_vpn_1
sudo ifconfig tap_g1 0.0.0.0 up
sudo ifconfig vpn_1 0.0.0.0 up
sudo ifconfig g1_vpn_1 0.0.0.0 up

sudo ovs-ofctl add-flow vpnbr1 in_port=1,actions=output:2
sudo ovs-ofctl add-flow vpnbr1 in_port=2,actions=output:1

sudo ovs-ofctl del-flows vpnbr1 in_port=1
sudo ovs-ofctl del-flows vpnbr1 in_port=2

#

#
# sudo ovs-vsctl add-br vpn_ovs
# sudo ovs-vsctl add-port vpn_ovs enp1s0f1
#
# sudo ip link add "ovs_vpn_1" type veth peer name "vpn_ovs_1"
# sudo ovs-vsctl -- add-port vpn_ovs "ovs_vpn_1" -- set interface "ovs_vpn_1" external_ids:container_id="1_ZURI_L2_vpn_1" external_ids:container_iface="vpn_ovs_1"
