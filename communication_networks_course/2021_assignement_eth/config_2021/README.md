#### Additional topologies

In this directory, we provide configuration files to build the topology we used
in the 2021 iteration of the project. We provide configuration files for different
sizes of the mini-Internet.

Please look at the 2021 assignment [text](https://github.com/nsg-ethz/mini_internet_project/blob/master/2021_assignment_eth/wiki)
to see how the L2, L3 and AS-level topologies look like.  

If you want to quickly try the mini-Internet on a small server/VM, you may want to try the topologies with 1 or 2 ASes.
To do this, just run the following commands if you want to use the 1-AS topology:

```
cp external_links_config_1.txt ../config/external_links_config.txt
cp AS_config_1.txt ../config/AS_config.txt
```

In the topology with 2 ASes, the two ASes are connected via the router ZURI, see `external_links_config_2.txt`.
If you want to try a larger mini-Internet, you may want to use the topology with 40 or 60 ASes.
