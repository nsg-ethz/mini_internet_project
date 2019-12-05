# The mini-Internet topology

In the directory you will find the default configuration files that define the topology used when building the mini-Internet. 
The files `layer2_hosts_config.txt`, `layer2_switches_config.txt` and `layer2_links_config.txt` define the L2 topology.
The default L2 topology is the following one:

<img src="l2network-crop.png" width="600" />

The file `router_config.txt` and `internal_links_config.txt` define the L3 topology. The default topology and the default IP address allocation scheme is depicted in the figure below. 

<img src="l3network-crop.png" width="800">

Finally, by default a mini-Internet with 20 ASes is built, and the figure below depicts the AS-level topology. There are Tier1 ASes, transit ASes, Stub ASes, as well as IXPs. ASes and IXPs are interconneted together via peer-2-peer links or provider/customer links. 

<img src="aslevel-crop.png" width="500">


