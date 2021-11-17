# The mini-Internet documentation

In this README, we first explain how to [install the required software](https://github.com/nsg-ethz/mini_internet_project/tree/master/platform#prerequisite). Then we show how to [build](https://github.com/nsg-ethz/mini_internet_project/tree/master/platform#build-the-mini-internet), [configure](https://github.com/nsg-ethz/mini_internet_project/tree/master/platform#configure-the-mini-internet-topology), [access](https://github.com/nsg-ethz/mini_internet_project/tree/master/platform#access-the-mini-internet) and [delete](https://github.com/nsg-ethz/mini_internet_project/tree/master/platform#delete-the-mini-internet) the mini-Internet. Finally, we explain the different [monitoring tools](https://github.com/nsg-ethz/mini_internet_project/tree/master/platform#use-the-monitoring-tools-and-services).

We run our mini-Internet on a server with Ubuntu 18.04 and the Linux 4.15.0 kernel (it also works on an Ubuntu 20.04 and the linux kernel 5.4.0).
For more details about the used default topology as well as other example topologies, please refer to the [config](config) directory. \
:information_source:  We allocate two cores to the docker containers, thus the server hosting the mini-Internet needs at least two cores. If you want to try it out with one core, you will have to update the [container_setup.sh](https://github.com/nsg-ethz/mini_internet_project/blob/master/platform/setup/container_setup.sh) script.

For further information about how we use the mini-Internet at ETH Zurich, and how we implemented it, please see our [technical report](https://arxiv.org/pdf/1912.02031.pdf).

## Prerequisite

To build the mini-Internet, you need to install the following software on the server which hosts the mini-Internet.

#### Install the Docker Engine

To run all the different components in the mini-Internet (hosts, switches, routers, ...) we use Docker containers.

Follow this [installation guide](https://docs.docker.com/install/linux/docker-ce/ubuntu/) to install docker.
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

#### Install OpenSSL

Make sure to use [OpenSSL 1.1.1](https://www.openssl.org/source/old/1.1.1/) (2018-Sep-11). If you want to use the latest OpenSSL version, then you need to use DH keys of size 2048 (see [here](https://github.com/nsg-ethz/mini_internet_project/blob/master/platform/setup/vpn_config.sh#L96)), but that will increase the startup time.

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

:warning: Make sure your server has enough resources to sustain this mini-Internet (around 32GB of memory and at least 4 CPU cores are recommended). Otherwise, look at section [configure the mini-Internet](https://github.com/nsg-ethz/mini_internet_project/blob/master/platform/README.md#configure-the-mini-internet-topology) for instructions on how to run a smaller mini-Internet.

:information_source: You may need to increase the number of INotify instances that can be created per real user ID with the command `fs.inotify.max_user_instances = 1024`.


#### Hosts, switches and routers can be automatically pre-configured

You can specify in the configuration files if you want the hosts, switches and routers to be pre-configured (with STP, OSPF, BGP, etc). In the sample configuration files that we provide (see [examples/config_2020](examples/config_2020), [examples/config_2019](examples/config_2019) and [examples/config_l2](examples/config_l2)), all the ASes will be automatically pre-configured. If you want the hosts, switches and routers in an AS not to be automatically configured, just replace "Config" with "NoConfig" in the [AS_config.txt](config/AS_config.txt) configuration file.

## Configure the mini-Internet topology

In the [config](config) directory, you can find all the configuration files used to define the topology of the mini-Internet.
In addition, we also provide multiple sample topologies (see [examples/config_2020](examples/config_2020), [examples/config_2019](examples/config_2019) and [examples/config_l2](examples/config_l2)). Of course, you can also define your own topology using the configuration files.

The config files are organized as follow:

```
config/
├── external_links_config.txt    [inter-AS links and policies] 
└── AS_config.txt                [per-AS topology & config]
    ├── router_config.txt                    [L3 internal topology]
    ├── internal_links_config.txt            [L3 internal topology]
    ├── layer2_switch_config.txt             ^
    ├── layer2_links_config.txt              |   [L2 topology]
    └── layer2_switches_config.txt           v   
```

#### List of ASes, with their L2 and L3 topologies

`AS_config.txt`: This file lists all the ASes and IXPs in the mini-Internet. By default, there are 20 ASes and 3 IXPs.
"Config" in the third column indicates whether the components (hosts, switches and routers) in the corresponding AS should pre-configured, otherwise write "NoConfig". In the topologies we provide, all the ASes are pre-configured by default.

The next columns allow to change the L2 and L3 topologies according to the AS.
More precisely, the fourth and fifth columns indicate the configuration files to use to build the L3 topology. For instance for AS 3 we use the L3 topology defined in the files `router_config_full.txt` and `internal_links_config.txt`. 
The next columns indicate the configuration files to use to build the L2 topologies. For instance for AS 3 we use the L2 topology defined in the files `layer2_switches_config.txt`, `layer2_hosts_config.txt` and `layer2_links_config.txt`.

#### Layer 2 topology

You can configure the layer 2 topology with the files `layer2_switches_config.txt`, `layer2_links_config.txt`, `layer2_hosts_config.txt`. Note that there can be several L2 networks in each AS. Each L2 network has a name. The one used by default in the [config](config) directory is called `UNIV`.

`layer2_switches_config.txt`: This file lists the switches in the L2 networks. The first column indicates the name of the L2 network. The second line indicates the name of the switch. By default, there are three switches (CERN, ETHZ and EPFL). The third column indicates whether one switch is connected to a L3 router, here by default CERN is connected to the router GENE and ETHZ is connected to the router ZURI. The fourth column indicates the MAC address used as an 'ID' to configure the switch. Finally, the fifth column indicates the bridge ID used in the Spanning Tree computation. Note that a router can only be connected to one L2 network, but a layer 2 network can be connected to one or more routers (see [examples/config_l2](examples/config_l2)). 
When a switch is connected to a L3 router, it must also be indicated in the third column of the config file `router_config_full.txt (or router_config_small.txt)`, which list the L3 routers. In this config file, the name of the L2 network must always be preceded by "L2-".

:information_source: Whenever you want to configure your own topology with your custom L2 network, you must follow the same naming convention. We recommend you to look into the directory [examples/config_l2](examples/config_l2) for more details. 

`layer2_links_config.txt`: This file indicates how the l2 switches are interconnected. For instance by default ETHZ is connected to CERN and EPFL, etc. The last two columns indicate the throughput and the delay of the link, respectively. The first and third columns indicate the name of the L2 network in which the switches in the second and fourth columns are, respectively. The L2 names should be identical since it is not possible to connect two switches that are in two different L2 network. 

`layer2_hosts_config.txt`: This file indicates the hosts that are in the layer 2 network, the docker image they are running and to which switch they are directly connected to. For instance the host student_1 is by default in the L2 network named UNIV, runs the docker image `thomahol/d_host` and is connected to CERN. The next two columns indicate the throughout and delay, respectively. The last column indicates the VLAN the host belongs to. Observe that a host can be a VPN server, in which case it must start with "vpn_".

#### Layer 3 topology

`router_config_full.txt (or router_config_small.txt)`: This file contains all the routers in the L3 topology. In the default L3 topology there are 8 routers. The second column indicates if a tool or service (such as the connectivity matrix or the DNS server) is connected to the network through the corresponding router. For instance, the DNS server is connected to LOND. The third column indicates whether a single host or a L2 network is connected to the router. In the default topology, both routers ZURI and GENE are connected to a L2 network, all the others are connected to a single host. In case a router is connected to a single host, the third column (after the semicolon) also indicates which docker image the host is running. Note that a router can be connected to a host even if it is also connected to a L2 network. Finally the last column indicates wether the students can access the router container with bash or can only access the CLI. `vtysh` means the students can only access the CLI whereas anything else means the students can access the router container using bash (via the `goto.sh` script, using the keyword `container` instead of `router`).

`internal_links_config_full.txt (or internal_links_config_small.txt)`: This is the internal topology. The first two columns indicate which pair of routers are interconnected, the last two columns indicate the throughput and delay of the link, respectively.

#### AS-level topology and policies

`external_links_config.txt`: This file describes the inter-AS links and policies, and which router in one AS is connected to which router in another AS. Let's take the following line as an example:

`1	ZURI	Provider	3	BOST	Customer	10000	1000	179.0.3.0/24`

This means that the router ZURI (2nd column) in AS 1 (1st column) is connected to the router BOST (5th column) in AS 3 (4th column). AS1 is the provider (3rd column) and AS3 is the customer (6th column). As usual, the 7th and 8th columns indicate the throughput and the delay, respectively. The last columns indicate the subnet to use for the eBGP session when the AS comes pre-configured (you can also write N/A instead, thus the subnet used for the eBGP session will be arbitrary).

Sometimes, an AS can also be connected to an IXP. To reduce the server load, an IXP AS contains only one router. Therefore, the 5th
column indicates N/A. An example:

`2	BARC	Peer	80	N/A	Peer	10000	1000	1,2,11,12`

This configuration line shows that the BARC router in AS 2 is connected to the IXP with AS number 80.
The last column (1,2,11,12) indicates to which participants the routes advertised by AS 2 should be propagated.
This last column is used when the configuration is automatically generated, otherwise the students have to use the correct BGP community values in order for their routes to be advertised to certain ASes only.

The file `subnet_config.sh` is used to configure the IP addresses following a particular scheme (see our [2020 assignment](../2020_assignment_eth/routing_project.pdf)), we recommend to not modify this file if you are using our topologies and want to use our IP address allocation scheme. In case you modify this file, you must keep the same name for each function, otherwise the mini-Internet will not start properly.

#### Change the size of the mini-Internet

You may want to run a smaller or larger mini-Internet. For instance, if you just want to quickly test the setup, or if you only have a small VM available, you should run a very small mini-Internet topology with only few ASes. Alternatively, if you want to run the mini-Internet for a class project, you may want to run a larger one with e.g., 60 ASes.
In the directory `config_2020`, you find working configuration files for different sizes of the mini-Internet. To use them, copy them to the `config` directory. The AS-level topologies follow the structure we used in the 2020 iteration of the mini-Internet project. 

To run a mini-Internet with only 1 AS, just copy the following files:

```
cp config_2020/AS_config_1.txt config/AS_config.txt
cp config_2020/external_links_config_1.txt config/external_links_config.txt
```

To run a mini-Internet with 60 ASes, copy the following files:

```
cp config_2020/AS_config_60.txt config/AS_config.txt
cp config_2020/external_links_config_60.txt config/external_links_config.txt
```

We also provide configuration files for a 2 ASes and a 40 ASes topology.

## Access the mini-Internet

You can access the mini-Internet in three ways.

#### Instructor access using docker

If you are the instructor and have access to the server hosting the mini-Internet, you can directly access the containers using the various docker commands. First, type `sudo docker ps` to get a list of all the containers running. The names of the hosts, switches and routers always follow the same convention. For instance, to access a shell of the LOND router in AS1, just use the following command:

`sudo docker exec -it 1_LONDrouter bash`

If you are in the router container, run `vtysh` to access the CLI of that router.
The following example shows 
you how to access the switch EPFL in the L2 network UNIV of AS3:

`sudo docker exec -it 3_L2_UNIV_EPFL bash`

Hosts and switches do not have a CLI, so once you are in the container, you can start configuring them. 


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
For instance to jump into the host connected to the router MIAM, use the following command:

```
./goto.sh MIAM host
```

If you want to access the router MIAM, write:

```
./goto.sh MIAM router
```

And if you want to access the switch CERN in the L2 network UNIV, use the following command:

```
./goto.sh UNIV CERN
```

Once in a host, switch or router, just type `exit` to go back to the proxy container.

Important to note, as some of our students are not too familiar with SSH, we give each student group a password to access their proxy container. However, it would also be possible to add the student's public keys to the corresponding proxy containers in order to achieve a key-based SSH authentication.

#### Student access with OpenVPN

Finally, you can also access the mini-Internet through a VPN.
In the file `config/layer2_hosts_config.txt`, the line starting with "vpn" corresponds to a L2-VPN server which will be automatically installed instead of a normal host. A L2-VPN is connected to a L2 switch (the one written in the 2nd column), and every user connected to this L2-VPN will be virtually connected to that L2 switch.

To use the VPN, a student must first install OpenVPN, and run it with the following command (in Ubuntu 18):

```
sudo openvpn --config client.conf
```

We provide the `client.conf` file below, where VPN_IP must be replaced by the IP address of the server hosting the mini-Internet. VPN_PORT defines to which VPN server we want to connect to.
You can find the port of the VPN servers by looking at their configuration file, which is located here: `groups/gX/vpn/vpn_Y/server.conf` with X the group number of Y the VPN ID for that group. 

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

The file `ca.crt` is automatically generated during the mini-Internet setup. It is available in the directory `groups/gX/vpn/vpn_Y` and must be given to the student.
Finally, the username is `groupX` (X is the group number) and the password is the same than the one used to access the proxy container through SSH.

When connected, the student should have an interface called `tap0` with a corresponding IP address. This interface is connected to the mini-Internet.

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
This file is bound to a file in the local filesystem according to this scheme: `groups/gX/<location>/looking_glass.txt` where X is the group
number and `<location>` is e.g. PARI.

Alternativley you can then simply periodically copy this file from the container (e.g., using `docker cp 1_PARIrouter:/home/looking_glass.txt .`) and make it available to the students for example over a web interface.

See `utils/upload_looking_glass.sh`.


#### Active probing

To run measurements between any two ASes, we must use a dedicated container called MEASUREMENT.
By default, we can access the measurement container over port 2099:

```
ssh -p 2099 root@<your_server_domain>
```

You can find the password in the file `groups/ssh_measurement.txt`. It should be distributed to all students such that they can access the MEASUREMENT container. \
In the MEASUREMENT container, we provide a script called `launch_traceroute.sh` that relies on `nping` and which can be used to launch traceroutes between any pair of ASes. For example if you want to run a traceroute from AS 1 to AS 2, simply run the following command:

```
root@ba1ccfaf2f55:~# ./launch_traceroute.sh 1 2.108.0.1
Hop 1:  1.0.199.1 TTL=0 during transit
Hop 2:  179.0.0.2 TTL=0 during transit
Hop 3:  2.0.1.2 TTL=0 during transit
Hop 4:  2.0.6.2 TTL=0 during transit
Hop 5:  2.108.0.1 Echo reply (type=0/code=0)
```

where 2.108.0.1 is an IP address of a host in AS2. You can see the path used by the packets to reach the destination IP.

By default, the measurement container is connected to the router ZURI in every transit AS. You can see this in the config file `config/router_config_full.txt`. The second column of the ZURI row is `MEASUREMENT` which means that the measurement container is connected to the ZURI router, but you can edit this file so that the measurement container is connected to another router instead. If for an AS none of the routers is connected to the measurement container (e.g., like in `config/router_config_small.txt`) then you can't run a traceroute from that AS using the measurement container. For instance in [examples/config_2020](examples/config_2020) configuration files, you can't use the measurement platform to run a traceroute from a Tier1 or a Stub AS.

#### Connectivity matrix

Another container called `MATRIX` is also connected to every AS. By looking at the config file `config/router_config_full.txt`, we can see to which router it is connected in every AS (MATRIX) and towards which router it sends ping requests in every other AS (MATRIX_TARGET). By default, the matrix container is connected to PARI, and the pings are destined to the ATLA routers.
Only the instructor can access the MATRIX container, from the server with:

```
sudo docker exec -it MATRIX bash
```

To generate the connectivity matrix, just run the following script (we recommend to run it from a tmux session so that it never stops):

```
cd /home
python ping.py
```

The html file `matrix.html` is then automatically generated and periodically updated. You can then download this file and make it available to the students on your website. We share the CSS files in the directory `docker_images/matrix/css`.

#### The DNS service

Finally, another container, connected to every AS and only available to the instructor runs a bind9 DNS server.
By looking at the file `config/router_config_full.txt`, we can see that the DNS container is connected to every LOND router.
The DNS server has the IP address 198.0.0.100/24 and as soon as the students have configured intra-domain routing and have advertised this subnet into OSPF, they should be able to reach the DNS server and use it.

For instance, a traceroute from ATLA-host to LOND-host returns the following output:

```
root@ATLA_host:/# traceroute 1.101.0.1
traceroute to 1.101.0.1 (1.101.0.1), 30 hops max, 60 byte packets
 1  ATLA-host.group1 (1.107.0.2)  0.653 ms  0.625 ms  0.632 ms
 2  NEWY-ATLA.group1 (1.0.11.1)  0.868 ms  0.861 ms  0.740 ms
 3  LOND-NEWY.group1 (1.0.8.1)  1.145 ms  0.973 ms  1.119 ms
 4  host-LOND.group1 (1.101.0.1)  1.435 ms  1.458 ms  1.422 ms
root@ATLA_host:/#
```
The naming convention is quite straightforward: XXXX-YYYY.groupZ, where XXXX the router where this IP address is configured, YYYY is the name of the router on the other end of the link (or "host" if there is a host). Finally Z is the AS number. The IP addresses used on the links connecting two ASes are not translated.

## Some additional useful tools and features

#### Restart a container

It can happen that a container crashes while the mini-Internet is running. For instance we have observed that the SSH containers sometimes fail if a student starts more than 100 processes in it (100 is the max number of processes that can run in this container). It is a hassle to restart a container and connect it to the other containers according to the topology, thus the script `restart_container.sh` is automatically generated and can be used to reconnect a container to the other containers automatically.

For instance if the container CONTAINER_NAME has crashed or has a problem, just run the following commands:

```
docker kill CONTAINER_NAME
docker start CONTAINER_NAME
./groups/restart_container.sh CONTAINER_NAME
```

Note: sometimes the MAC address on some interfaces must follow a particular scheme (for instance the ones connected to the MATRIX container). Configuring these MAC addresses must be done manually.

#### Saving routers and switches configuration

When building the mini-Internet, a script called `save_configs.sh` is automatically generated and aims at saving all the routers and switches configuration in a zip file. There is one `save_configs.sh` script for each group, which is available in the SSH proxy container of the corresponding group. A complementary script `restore_configs.sh` is also available and restores a router's configuration (or all routers) from a saved configuration. Reloading a switch's configuration is not supported.

#### Restarting ospfd

Students may encounter the message _For this router-id change to take effect, save config and restart ospfd_ when configuring a router. The `restart_ospfd.sh` script deletes and reinstalls the OSPF configuration running on a given router. Deleting and reinstalling the OSPF configuration effectively restarts ospfd and will cause the new router-id to take effect.

#### MPLS and Multicast

The mini-Internet can support MPLS and Multicast. To activate MPLS you must turn on the ldp daemon by replacing `ldpd=no` with `ldpd=yes` in `config/daemons`. Similarly, for Multicast you need to replace `pimd=no` with `pimd=yes`. 
The [`hostm`](docker_images/hostm/Dockerfile) docker image comes with multicast tools such as `smcroute` or `mtools` and can be used to test multicast. The `vlc` docker image comes vlc and can stream a multicast video.

