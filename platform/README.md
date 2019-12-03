## Prerequisites

The following installation guide works for Ubuntu 18.

#### Install the Docker Engine
```
sudo apt-get update
sudo apt install docker.io
```

For further information, see the [installation guide](https://docs.docker.com/install/linux/docker-ce/ubuntu/).

#### Install OpenVSwitch
```
sudo apt-get install openvswitch-switch
```

For further information, see the [installation guide](http://docs.openvswitch.org/en/latest/intro/install/).

#### Install OpenVPN

```
sudo apt-get install openvpn
```

## Run the mini-Internet

Clone this directory in your server, and go the directory `platform`.
```
cd platform
```

Then run the startup script:
```
sudo startup.sh
```

By default, this will run a mini-Internet with 20ASes. Make sure your server has enough resources to sustain this mini-Internet (e.g., around 64GB of memory and 8 CPU cores are recommended). Otherwise, see in section [configure the mini-Internet](README.md#configure-the-mini-internet) how to run a mini-Internet with only one AS.

## Delete the mini-Internet

The are two ways to delete the mini-Internet. First, you can delete all the virtual ethernet pairs, docker containers and ovs switches used in the mini-Internet, with the following command.
```
sudo ./cleanup/cleanup.sh .
```

However, this script used the configuration files, so is they have changed since the time the mini-Internet was built, not all the componenents will be deleted, and this will make problems if you want to run a new mini-Internet. We thus also provide you with a script that delete *all* the ethernet pairs, containers and switches, including the ones not used in for mini-Internet.
```
sudo ./hard_reset.sh
```

## Configure the mini-Internet

In the `config` directory, you can find all the configuration files used to define the topology of the mini-Internet.

#### Layer 2 topology

`layer2_switches_config.txt`: The file lists the switches in the L2 network. By default there are four switches (ETH-ZENT, ETH-HONG, ETH-IRCH, ETH-OERL). The second column indicates whether the switch is connected to the L3 router, here by default ETH-ZENT is connected to the router. Finally the third column indicates the MAC address used as an 'ID' to configure the switch.

`layer2_links_config.txt`: This file indicates how the l2 switches are interconnected. For instance by default ETH-ZENT is connected to ETH-IRCH, ETH-ZENT is connected to ETH-OERL, etc. THe last two columns indicate the throughput and the delay of the link, respectively.

`layer2_hosts_config.txt`: This file indicates the hosts that are in the layer 2 network, and to which they are directly connected. For instance the host student_1 is by default connected to ETH-IRCH. The next two columns indicate the throughout and delay, respectively. The last column indicates in which VLAN is each host. Also not that a host can be a VPN server, in which case it must start with "vpn_". 

`router_config.txt`:

`internal_links_config.txt`:

`AS_config.txt`:

`external_links_config.txt`:

## Access the mini-Internet


