# The mini-Internet platform

The documentation is available in the [**wiki**](https://github.com/nsg-ethz/mini_internet_project/wiki).

### 2025 Routing project (23 March!)

-[x] Design this year's topology (Central Europe).

-[x] Update and fix routinator and krill

-[x] Fix the autograder

-[x] Adjust and test the configuration for the new topology using the same tasks as last year.

-[x] Fix saving (some issue with the script?)

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

-[x] Add ./go-to MEASUREMENT?

-[x] Create a MEASUREMENT Welcome message.

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