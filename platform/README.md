# The mini-Internet platform

The documentation is available in the [**wiki**](https://github.com/nsg-ethz/mini_internet_project/wiki).


## Things to improve and debug for next year:
- Some of the scripts to use *after setup* are fickle; e.g. the one to configure existing ASes; the scripts just run some commands in ASes, regardless of what has been already configured. If used on a half-configured AS, this can lead to a big mess. Can we make this more robust?
- The proxy containers need regular pruning so they don’t hit the process limit → fix that problem at the source.
- Fix the bug where traceroute from hosts don’t go through all the load-balanced paths but seem to all go over the same
- Make sure that the hostnames don’t resolve to the IPs of the docker containers, so that traceroutes don’t use the docker network if the students type in traceroute MILA\_router
- Fix the problem that groups need access to AS1 for some tasks, either distribute krill and vpn secret or advertise route to AS1 from more places
- Allow webpage to be accessed while connected to the VPN
- Change the color of the invalid entries in the matrix to something darker to make it easier to distinguish from green, for color blindness reasons
- Change the meaning of yellow in the matrix to avoid confusion
- Fix the performance problem of the wg\_observer process when no sleep time environment variable is set
- History creates zombie processes if enabled but no gitlab token set 


## Checklist:

### 2025 Routing project

-[ ] Design this year's topology (Central Europe).

-[ ] Update and fix routinator and krill

-[ ] Fix the autograder

-[ ] Adjust and test the configuration for the new topology using the same tasks as last year.

-[ ] Fix saving (some issue with the script?)

-[ ] Fix the website/krill unreachable issue.

-[ ] Finish and test the new restart script for each containers.

-[ ] Adjust the wiki

-[ ] Contact sysadmin to open ports.

-[ ] Launch a medium-sized topology and contact student TAs to solve it.

-[ ] Generate student Gitlab repositories.

-[ ] Search for all FIXME and TODOs and address them.

-[ ] Is the examples folder of any use nowadays? Maybe just remove it.

-[ ] Can I get from one ssh proxy to another via the network? Or ping others via the ssh proxy?

-[ ] Test restarting any container.

-[ ] Plenty of scripts in /groups are not used anymore. Are they still created? check that.

-[ ] Uncomment hijack.

-[ ] VPN

-[ ] Add ./go-to MEASUREMENT?

-[ ] Create a MEASUREMENT Welcome message.

-[ ] Ask student TAs to check: downloading configs, L2 stuff, 6in4 tunnel, goto scripts, dns output.

### Checklist for the final reboot.

-[ ] Do router-host interfaces show up in DNS, e.g. run a traceroute from CAIR host in group 10 to host.cape.group10, and see whether the first hop 10.101.0.2 is resolved.

-[ ] Is one of the provider/customer links delayed? 25ms vs 2.5ms.

-[ ] Check the ./goto script for TA ASes e.g. AS 11; there should not be multiple router entries.

-[ ] Check that saving does not throw an error anymore.

### Critical tasks remaining

-[ ] Set up automated snapshots. I think putting it in a container would be best.

-[ ] Go over TODOs and FIXMEs and see if anything really important is left.

### Things to do when merging back into the main branch

-[ ] Document the ALL option in l3 configs in the GitHub wiki.

-[ ] Address all remaining TODOs and FIXMEs.

-[ ] Clean up obsolete scripts anywhere

-[ ] Add a config file for each container name and config files and remove any hardcoded variable in any script.

-[ ] Clean up VPN scripts (as they are not tested)

-[ ] (Optional) Separate the config load part into separate scripts that can be merged with `layer2_config.sh` and `router_config.sh` later.
