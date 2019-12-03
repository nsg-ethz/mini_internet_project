# The mini-Internet documentation

## Prerequisite

The following installation guide works for Ubuntu 18 and the Linux 4.15.0 kernel.

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

## Configure the mini-Internet topology

In the `config` directory, you can find all the configuration files used to define the topology of the mini-Internet.

#### Layer 2 topology

`layer2_switches_config.txt`: The file lists the switches in the L2 network. By default there are four switches (ETH-ZENT, ETH-HONG, ETH-IRCH, ETH-OERL). The second column indicates whether the switch is connected to the L3 router, here by default ETH-ZENT is connected to the router. Finally the third column indicates the MAC address used as an 'ID' to configure the switch.

`layer2_links_config.txt`: This file indicates how the l2 switches are interconnected. For instance by default ETH-ZENT is connected to ETH-IRCH, ETH-ZENT is connected to ETH-OERL, etc. THe last two columns indicate the throughput and the delay of the link, respectively.

`layer2_hosts_config.txt`: This file indicates the hosts that are in the layer 2 network, and to which they are directly connected. For instance the host student_1 is by default connected to ETH-IRCH. The next two columns indicate the throughout and delay, respectively. The last column indicates in which VLAN is each host. Also not that a host can be a VPN server, in which case it must start with "vpn_". 

#### Layer 3 topology

`router_config.txt`: This file lists the routers. By default there are 8 routers. The second column indicates if a server (such as the connectivity matrix or the DNS server) is connected the to the network through the corresponding router. For instance, the DNS server is connected to ROMA. Finally the last column indicates whether a single host or a L2 network is connected to the router. By default, only the router ZURI is connected to a L2 network, all the others are connected to a single host.

`internal_links_config.txt`: This is the internal topology. The first two columns indicate which pair of routers are interconnected, the last two columns indicate the throughput and delay of the link, respectively.

#### AS-level toplogy

`AS_config.txt`: This file lists all the ASes and IXPs in the mini-Internet. By default, there are 20 ASes and 3 IXPs.

`external_links_config.txt`: This file describes the AS-level topology, and which router in one AS is connected which router in another AS. Let us take this line as example:

`1	HOUS	Provider	3	LOND	Customer	10000	1000	N/A`

This means that the router HOUS (2nd column) in AS 1 (1st column) is connected to the router LOND (5th column) in AS 3 (4th column). AS1 is the provider (3rd column) and AS3 is the customer (6th column).

Sometimes, an AS can also be connected to an IXP, for instance:

`2	BARC	Peer	80	N/A	Peer	10000	1000	1,2,11,12`

When the 5th column is N/A, it means it is an IXP, and the AS number of the IXP is 80.
the column (1,2,11,12) indicate to which participants the routes advertised by AS2 should be propagated.

As usual, the 7th and 8th columns indicate the throughput and the bandwidth, respectively.

The file `subnet_config.sh` and `daemons` are used to configure the IP addresses and the routers, we recommend not to modify these files.


#### Change the size of the mini-Internet

You may want to run a smaller of larger mini-Internet. For instance, if you just want to quickly experience the mini-Internet, or if you only have a small VM, you should run a very small Internet with only AS. Alternatively, if you want to run the mini-Internet for a class project, you may to run a larger one with e.g., 60 ASes. 
In the directory `config_2019` with provide you with a set of configuration files for different size of the mini-Internet that you can just copy/past in the `config` directory. The AS-level topologies follow the structure we used in the 2019 iteration of the mini-Internet project. We always use the L3 and L2 topologies.

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

## Access the mini-Internet

You can access the mini-Internet in two ways.

#### Instructor access with docker

First, if you are the instructors and have access to the server hosting the mini-Internet, you can directly access the containers using the docker commands. First, type `sudo docker ps` to get a list of all the containers running. The names of the hosts, switches and routers always follow the same convention. To access the router LOND in AS1, just use the following command:

`sudo docker exec -it 1_LONDrouter bash`

Then, run `vtysh` to access the CLI of that router. Just change the name according the container you want to access. 

#### Student access with SSH

To enable the student access through SSH, first the instructor needs to enable the ssh port forwarding with the following command:

`sudo ./portforwarding.sh`

Make sure the following options are se to true in `/etc/sshd_config`:
```
GatewayPorts yes
PasswordAuthentication yes
AllowTcpForwarding yes
```

Then, the students can connect from outside. First, the students have to connect to the ssh proxy container:

```ssh -p [2000+X] root@server.ethz.ch```

with X the group number. The passwords of the groups are available in the file `groups/ssh_passwords.txt`

Once in the proxy container, the student can use the `goto.sh` script to access a host, switch or router. 
For instance to jump into the host connected to the router ABID, use the following command:

```
./goto ABID host
```

Once in a host, switch or router, just type `exit` to go back to the proxy container.


## Use the monitoring tools and services

We now explain how are built the different monitoring tools and services, and how to use them.

#### Looking glass

Every container running a router pulls the routing table from the FRRouting CLI and stores it in `/home/looking_glass.txt`.
Then, you can simply periodically get that file with e.g., `docker cp 1_ABIDrouter:/home/looking_glass.txt .` and make it available to the students, for instance on a web interface.

#### Active probing

To run measurements between any two ASes, we must use a dedicated container called the management container. 
To access the management container, we must use the port 2099:

```
ssh -p 2099 root@server.ethz.ch
```

The password is available in the file `groups/ssh_mgt.txt`, and should be made available to the students do that they can access it. \
In the management VM, we provide a script called `launch_traceroute.sh` that relies on `nping` you which you can use to launch traceroute between any two ASes. For example if you want to run a traceroute from AS 1 to AS 2, simply run the following command

```
root@c7a60237994a:~# ./launch_traceroute.sh 1 2.101.0.1
Hop 1:  1.0.199.1 TTL=0 during transit
Hop 2:  1.0.8.2 TTL=0 during transit
Hop 3:  179.24.1.2 TTL=0 during transit
Hop 4:  2.0.8.1 TTL=0 during transit
Hop 5:  2.0.1.1 TTL=0 during transit
Hop 6:  2.101.0.1 Echo reply (type=0/code=0)
```

where 2.101.0.1 is an IP address of a host in AS2 (here we tested on a topology with 2 ASes). You can see the path used by the packets to reach the destination IP. 

By default, the management container is connected to the router ZURI in every AS. You can see this in the config file `config/router_config.txt`. The second column of the ZURI row is `MGT` which means that the management container is connected to the ZURI router, but you can edit this file so that the management VM is connected to another router instead. 

#### Connectivity matrix

Another container called `MATRIX` is also connected to every AS. By looking at the config file `config/router_config.txt`, we can see to which router it is connected in every AS and towards which router it sends ping requests in every other AS. By default, the matrix container is connected to TOKY and HOUS. The pings are sent from TOKY and are destined to the HOUS routers. 
Only the instructor can access the MATRIX container, from the server with:

```
sudo docker exec -it MATRIX bash
```

To generate the connectivity matrix, just run the following script:
```
cd /home
.ping_all_groups.sh
```

The connectivity matrix is then available in the file `/home/connectivity.txt`, where 1 means connectivity, and 0 means no connectivity. You can then periodically download this file and making it available to the students on e.g., a web interface. 

#### The DNS service

Finally, another container, connected to every AS and only available to the instructor run a bind9 DNS server.
By looking at the file `config/router_config.txt`, we can see that the DNS container is to connected to every router ROMA.
As soon as the students have configured intra-domain routing, they should be able to use the DNS.

For instance, a traceroute from HOUS-host to ABID-host will return this:

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
