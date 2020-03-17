# The mini-Internet topology

This directory contains the configuration files for the topology we used in the 2019 iteration of the the mini-Internet project.
The files `layer2_hosts_config.txt`, `layer2_switches_config.txt` and `layer2_links_config.txt` define the L2 topology in transit ASes.
The L2 topology in is the following one:

<img src="figures/l2network-crop.png" width="600" />

The files `router_config.txt` and `internal_links_config.txt` define the L3 topology in transit ASes.
The L3 topology and the IP address allocation scheme for each AS is depicted in the figure below.

<img src="figures/l3network-crop.png" width="800">

Finally, by default a mini-Internet with 20 ASes is built. The figure below depicts the AS-level topology. There are Tier1 ASes, transit ASes, Stub ASes, as well as IXPs. ASes and IXPs are interconnected via peer-2-peer links or provider/customer links.

<img src="figures/aslevel-crop.png" width="500">


#### Additional topologies

In this directory, we provide configuration files for different sizes of the mini-Internet.
If you want to quickly try the mini-Internet on a small server/VM, you may want to try the topologies with 1 or 2 ASes.
In the topology with 2 ASes, the two ASes are connected via the router TOKY, see `external_links_config_2.txt`.
If you want to try a larger mini-Internet, you may want to use the topology with 40 or 60 ASes.

We always use the same L2 and L3 topologies.
When you make your own topology, make that the ASes are ordered in the file `AS_config.txt`.
