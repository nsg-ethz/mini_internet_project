# The mini-Internet documentation

In this README, we first explain how to [install the required software](https://github.com/nsg-ethz/mini_internet_project/tree/master/platform#prerequisite). Then we show how to [build](https://github.com/nsg-ethz/mini_internet_project/tree/master/platform#build-the-mini-internet), [configure](https://github.com/nsg-ethz/mini_internet_project/tree/master/platform#configure-the-mini-internet-topology), [access](https://github.com/nsg-ethz/mini_internet_project/tree/master/platform#access-the-mini-internet) and [delete](https://github.com/nsg-ethz/mini_internet_project/tree/master/platform#delete-the-mini-internet) the mini-Internet. Finally, we explain the different [monitoring tools](https://github.com/nsg-ethz/mini_internet_project/tree/master/platform#use-the-monitoring-tools-and-services).

We run our mini-Internet on a server with Ubuntu 18.04 and the Linux 4.15.0 kernel.
For more details about the used default topology as well as other example topologies, please refer to the [config](config) directory.

For further information about how we use the mini-Internet at ETH Zurich, and how we implemented it, please see our [technical report](https://arxiv.org/pdf/1912.02031.pdf).

## Prerequisite

To build the mini-Internet, you need to install the following software on the server which hosts the mini-Internet.

#### Install the Docker Engine

To run all the different components in the mini-Internet (hosts, switches, routers, ...) we use Docker containers.

```
sudo apt-get update
sudo apt install docker.io
```

For further information, see the [installation guide](https://docs.docker.com/install/linux/docker-ce/ubuntu/).
In the directory `docker_images` you can find all the Dockerfile and docker-start files used to build the containers.
In case you want to add some functionalities into some of the docker containers, you can
update these files and build you own docker images:

```
docker build --tag=your_tag your_dir/
```

Then, you have to manually update the scripts in the `setup` directory and run
your custom docker images instead of the ones we provide by default.


#### Install Open vSwitch

We use the Open vSwitch framework in two ways: (i) to build the L2 component of the mini-Internet and (ii) to connect Docker containers together.

```
sudo apt-get install openvswitch-switch
```

For further information, see the [installation guide](http://docs.openvswitch.org/en/latest/intro/install/).

#### Install OpenVPN

Finally, we also need Open VPN which allows the students to connect their own devices to the mini-Internet.

```
sudo apt-get install openvpn
```

## Build the mini-Internet

To build the mini-Internet, first clone this repository to your server, and go to the directory `platform`.
```
cd platform
```

Then run the startup script:
```
sudo ./startup.sh
```

By default, this will run a mini-Internet with 20ASes.
When building the mini-Internet, a directory called `groups` is created and all the configuration files, passwords, automatically-generated scripts, etc will be stored in this directorty.

:warning: Make sure your server has enough resources to sustain this mini-Internet (around 64GB of memory and at least 8 CPU cores are recommended). Otherwise, look at section [configure the mini-Internet](https://github.com/nsg-ethz/mini_internet_project/blob/master/platform/README.md#configure-the-mini-internet-topology) for instructions on how to run a smaller mini-Internet.

## Configure the mini-Internet topology

In the [config](config) directory, you can find all the configuration files used to define the topology of the mini-Internet.
In addition, we also provide multiple sample topologies. Of course, you can also define your own topology using the configuration files.

#### Layer 2 topology

`layer2_switches_config.txt`: This file lists the switches in the L2 network. By default there are four switches (ETH-ZENT, ETH-HONG, ETH-IRCH, ETH-OERL). The second column indicates whether one switch is connected to a L3 router, here by default ETH-ZENT is connected to a router. Finally the third column indicates the MAC address used as an 'ID' to configure the switch.

`layer2_links_config.txt`: This file indicates how the l2 switches are interconnected. For instance by default ETH-ZENT is connected to ETH-IRCH, ETH-ZENT is connected to ETH-OERL, etc. The last two columns indicate the throughput and the delay of the link, respectively.

`layer2_hosts_config.txt`: This file indicates the hosts that are in the layer 2 network, and to which switch they are directly connected to. For instance the host student_1 is by default connected to ETH-IRCH. The next two columns indicate the throughout and delay, respectively. The last column indicates the VLAN the host belongs to. Observe that a host can be a VPN server, in which case it must start with "vpn_".

#### Layer 3 topology

`router_config.txt`: This file contains all the routers in the L3 topology. In the default L3 topology there are 8 routers. The second column indicates if a tool or service (such as the connectivity matrix or the DNS server) is connected to the network through the corresponding router. For instance, the DNS server is connected to ROMA. Finally the last column indicates whether a single host or a L2 network is connected to the router. In the default topology, only the router ZURI is connected to a L2 network, all the others are connected to a single host.

`internal_links_config.txt`: This is the internal topology. The first two columns indicate which pair of routers are interconnected, the last two columns indicate the throughput and delay of the link, respectively.

#### AS-level topology

`AS_config.txt`: This file lists all the ASes and IXPs in the mini-Internet. By default, there are 20 ASes and 3 IXPs.
"Config" in the third column indicates whether the components (hosts, switches and routers) in the corresponding AS should pre-configured, otherwise write "NoConfig". In the topologies we provide, all the ASes are pre-configured by default.

`external_links_config.txt`: This file describes the AS-level topology, and which router in one AS is connected to which router in another AS. Let's take the following line as an example:

`1	HOUS	Provider	3	LOND	Customer	10000	1000	N/A`

This means that the router HOUS (2nd column) in AS 1 (1st column) is connected to the router LOND (5th column) in AS 3 (4th column). AS1 is the provider (3rd column) and AS3 is the customer (6th column).

Sometimes, an AS can also be connected to an IXP. To reduce the server load, an IXP AS contains only one router. Therefore, the 5th
column indicates N/A. An example:

`2	BARC	Peer	80	N/A	Peer	10000	1000	1,2,11,12`

This configuration line shows that the BARC router in AS 2 is connected to the IXP with AS number 80.
The last column (1,2,11,12) indicates to which participants the routes advertised by AS 2 should be propagated.
This last column is used when the configuration is automatically generated, otherwise it is the students that
have to use the correct BGP community values in order for their routes to be advertised to certain ASes only.

As usual, the 7th and 8th columns indicate the throughput and the bandwidth, respectively.

The file `subnet_config.sh` is used to configure the IP addresses following a particular scheme (see our [2019 assignment](https://github.com/nsg-ethz/mini_internet_project/blob/master/2019_assignement_eth/mini_internet_project.pdf)), we recommend to not modify these file if you are using our topologies and want to use our IP address allocation scheme. In case you modify this file, you must keep the same name for each function, otherwise the mini-Internet will not start properly.

#### Change the size of the mini-Internet

You may want to run a smaller or larger mini-Internet. For instance, if you just want to quickly test the setup, or if you only have a small VM available, you should run a very small mini-Internet topology with only few ASes. Alternatively, if you want to run the mini-Internet for a class project, you may want to run a larger one with e.g., 60 ASes.
In the directory `config_2019`, you find working configuration files for different sizes of the mini-Internet. To use them, copy them to the `config` directory. The AS-level topologies follow the structure we used in the 2019 iteration of the mini-Internet project. For each of the different mini-Internet AS-level topologies we use the same L3 and L2 topologies.

To run a mini-Internet with only 1 AS, just copy the following files:

```
cp config_2019/AS_config_1.txt config/AS_config.txt
cp config_2019/external_links_config_1.txt config/external_links_config.txt
```

To run a mini-Internet with 60 ASes, copy the following files:

```
cp config_2019/AS_config_60.txt config/AS_config.txt
cp config_2019/external_links_config_60.txt config/external_links_config.txt
```

We also provide configuration files for a 2 ASes and a 40 ASes topology.

## Access the mini-Internet

You can access the mini-Internet in three ways.

#### Instructor access using docker

If you are the instructor and have access to the server hosting the mini-Internet, you can directly access the containers using the various docker commands. First, type `sudo docker ps` to get a list of all the containers running. The names of the hosts, switches and routers always follow the same convention. For instance, to access a shell of the LOND router in AS1, just use the following command:

`sudo docker exec -it 1_LONDrouter bash`

If you are in the router container, run `vtysh` to access the CLI of that router.

#### Student access with SSH

Students first access a proxy container from where they can directly go to any device (router, host, ...) belonging to their AS.
To enable the student access through SSH, first make sure the following options are set to true in `/etc/sshd_config` on your host server:

```
GatewayPorts yes
PasswordAuthentication yes
AllowTcpForwarding yes
```

and restart the ssh service: `sudo service ssh restart`

Then, enable SSH port forwarding with the following command:

`sudo ./portforwarding.sh`

Now, the students should be able to connect from the outside. First, the students have to connect to the ssh proxy container:

```ssh -p [2000+X] root@<your_server_domain>```

with X their corresponding AS number (group number). The passwords of the groups are automatically generated with the `openssl`'s rand function and are available in the file `groups/ssh_passwords.txt`

Once in a proxy container, a student can use the `goto.sh` script to access a host, switch or router.
For instance to jump into the host connected to the router ABID, use the following command:

```
./goto ABID host
```

If you want to jump the the router connected to the router ABID, write:

```
./goto ABID router
```

And if you to access the switch ETH-IRCH in the L2 network connected to the router ZURI, use the following command:

```
./goto ZURI ETH-IRCH
```

Once in a host, switch or router, just type `exit` to go back to the proxy container.

Important to note, as some of our students are not too familiar with SSH, we give each student group a password to access their proxy container. However, it would also be possible to add the student's public keys to the corresponding proxy containers in order to achieve a key-based SSH authentication.

#### Student access with OpenVPN

Finally, you can also access the mini-Internet through a VPN.
In the file `config/layer2_hosts_config.txt`, the line starting with "vpn" corresponds to a L2-VPN server which will be automatically installed instead of normal host. A L2-VPN is connected to a L2 switch (the one written in the 2nd column), and every user connected to this L2-VPN will be virtually connected to that L2 switch.

To use the VPN, a student must first install OpenVPN, and run it with the following command (in Ubuntu 18):

```
sudo openvpn --config client.conf
```

We provide the `client.conf` file below, where VPN_IP must be replace by the IP address of the server hosting the mini-Internet. VPN_PORT defines to which VPN server we want to connect to.
To find the port of a specific VPN server, we use the following convention: the port of the n-th VPN server in group X is 1000+(X\*m)+(n-1) where m is number of VPN servers per AS (i.e., 2 by default). For instance, to access `vpn_4` in group 11, the port is 1000+(11\*2)+1 = 1023.

```
client
remote VPN_IP VPN_PORT
dev tap
proto udp
resolv-retry infinite
nobind
persist-key
persist-tun
ca ca.crt
cipher AES-256-CBC
verb 3
auth-user-pass
```

The file `ca.crt` is automatically generated during the mini-Internet setup. It is available in the directory `groups/gX/vpn/vpn_n` and must be given to the student.
Finally, the username is `groupX` (X is the group number) and the password is the same than the one used to access the proxy container.

When connected, the student should have an interface called `tap` with a corresponding IP address. This interface is connected to the mini-Internet.

## Delete the mini-Internet

The are two ways to delete the mini-Internet. First, you can delete all the virtual ethernet pairs, docker containers, OVS switches and OpenVPN processes used in the mini-Internet, with the following command:
```
sudo ./cleanup/cleanup.sh .
```

However, this script uses the configuration files, thus if they have changed since the time the mini-Internet was built, or if the mini-Internet did not setup properly, it might be that not all the components get deleted. That could be problematic if you try to start a new mini-Internet. We thus also provide a script that deletes *all* the ethernet pairs, containers and switches.

:warning: This also includes containers, switches and ethernet pairs which do not belong to the mini-Internet (e.g., your very important Docker container)!!!
```
sudo ./cleanup/hard_reset.sh
```

## Use the monitoring tools and services

The following section explains how we build and use the different monitoring tools and services.

#### Looking glass

Every container which runs a router pulls the routing table from the FRRouting CLI every 30 seconds and stores it in `/home/looking_glass.txt`.
You can then simply periodically copy this file from the container (e.g., using `docker cp 1_ABIDrouter:/home/looking_glass.txt .`) and make it available to the students for example over a web interface.

#### Active probing

To run measurements between any two ASes, we must use a dedicated container called MGT (for "management").
By default, we can access the management container over port 2099:

```
ssh -p 2099 root@server.ethz.ch
```

You can find the password in the file `groups/ssh_mgt.txt`. It should be distributed to all students such that they can access the MGT container. \
In the management VM, we provide a script called `launch_traceroute.sh` that relies on `nping` and which can be used to launch traceroutes between any pair of ASes. For example if you want to run a traceroute from AS 1 to AS 2, simply run the following command:

```
root@c7a60237994a:~# ./launch_traceroute.sh 1 2.101.0.1
Hop 1:  1.0.199.1 TTL=0 during transit
Hop 2:  1.0.8.2 TTL=0 during transit
Hop 3:  179.24.1.2 TTL=0 during transit
Hop 4:  2.0.8.1 TTL=0 during transit
Hop 5:  2.0.1.1 TTL=0 during transit
Hop 6:  2.101.0.1 Echo reply (type=0/code=0)
```

where 2.101.0.1 is an IP address of a host in AS2 (here we used the topology with 2 ASes). You can see the path used by the packets to reach the destination IP.

By default, the management container is connected to the router ZURI in every AS. You can see this in the config file `config/router_config.txt`. The second column of the ZURI row is `MGT` which means that the management container is connected to the ZURI router, but you can edit this file so that the management VM is connected to another router instead.

#### Connectivity matrix

Another container called `MATRIX` is also connected to every AS. By looking at the config file `config/router_config.txt`, we can see to which router it is connected in every AS and towards which router it sends ping requests in every other AS. By default, the matrix container is connected to TOKY, and the pings are destined to the HOUS routers.
Only the instructor can access the MATRIX container, from the server with:

```
sudo docker exec -it MATRIX bash
```

To generate the connectivity matrix, just run the following script:

```
cd /home
./ping_all_groups.sh
```

The connectivity matrix is then available in the file `/home/connectivity.txt`, where 1 means connectivity, and 0 means no connectivity. You can then periodically download this file and making it available to the students on e.g., a web interface.

#### The DNS service

Finally, another container, connected to every AS and only available to the instructor runs a bind9 DNS server.
By looking at the file `config/router_config.txt`, we can see that the DNS container is connected to every ROMA router.
The DNS server has the IP address 198.0.0.100/24, as soon as the students have configured intra-domain routing and have advertised this subnet into OSPF, they should be able to reach the DNS server and use it.

For instance, a traceroute from HOUS-host to ABID-host returns the following output:

```
root@HOUS_host:~# traceroute  1.108.0.1 --resolve-hostnames
traceroute to 1.108.0.1 (1.108.0.1), 64 hops max
  1   1.106.0.2 (HOUS-host.group1)  0.394ms  0.005ms  0.003ms
  2   1.0.6.1 (LOND-HOUS.group1)  0.143ms  0.145ms  0.129ms
  3   1.0.2.2 (BARC-LOND.group1)  2.159ms  2.168ms  2.150ms
  4   1.0.11.2 (ABID-BARC.group1)  2.199ms  2.277ms  2.253ms
  5   1.108.0.1 (host-ABID.group1)  2.383ms  2.289ms  2.290ms
```

Observe that we must use the option `--resolve-hostnames` to make traceroute resolve the hostnames.
