# The mini-Internet platform

The documentation is available in the [**wiki**](https://github.com/nsg-ethz/mini_internet_project/wiki).

### 2024 Routing project (25 March!)

-[x] Fix the website/krill unreachable issue.

-[ ] Finish and test the new restart script for each containers.
     Alex: I added the MATRIX because I needed to restart it :D

-[x] Design this year's topology (Africa).

-[x] Adjust and test the configuration for the new topology using the same tasks as last year.

-[ ] Adjust the matrix based on Laurent's feedback.
     Allow to disable validity checking.
     Alex: Need to update webserver, not matrix.
     Not sure if reallt needed.

-[x] Adjust the wiki based on Romain and Laurent's feedback

    - [x] mention `advertised-route` in the wiki
    - [x] more on community list semantics
    - [x] adjust command examples ,e.g., `neighbor 11.11.11.11`

-[x] Contact sysadmin to open ports.

-[x] Launch a medium-sized topology and contact student TAs to solve it.

-[ ] Generate student Gitlab repositories.

-[ ] Search for all FIXME and TODOs and address them.

-[x] Test launch traceroute and the matrix. I'm not sure I understand the matrix updates.

-[x] Test goto commands, also in stub and tier1.

-[ ] Is the examples folder of any use nowadays? Maybe just remove it.

-[x] Can I get from one ssh proxy to another via the network? Or ping others via the ssh proxy?
     I think this is working as intended.

-[ ] Test restarting any container.

-[ ] Plenty of scripts in /groups are not used anymore. Are they still created? check that.

-[x] Uncomment hijack.

-[ ] VPN?

-[x] Add ./go-to MEASUREMENT?

-[x] Create a MEASUREMENT Welcome message.


-[x] Ask student TAs to check: downloading configs, L2 stuff, 6in4 tunnel, goto scripts, dns output.

-[x] Collect all variables in one file for easier config.

-[x] Add new matrix flags.

-[x] Fix saving (some issue with the script?)

### Checklist for the final reboot.

I've done a couple of fixes that won't show up until the final reboot.
Here's a checklist of things to verify.

-[x] Do router-host interfaces show up in DNS, e.g. run a traceroute from CAIR host in group 10 to host.cape.group10, and see whether the first hop 10.101.0.2 is resolved.

-[x] Is one of the provider/customer links delayed? 25ms vs 2.5ms.

-[x] Check the ./goto script for TA ASes e.g. AS 11; there should not be multiple router entries.

-[x] Check that saving does not throw an error anymore.

### Critical tasks remaining

-[x] Set up automated snapshots. I think putting it in a container would be best.

-[x] Fix the hijack (other topology was needed).

-[x] Go over TODOs and FIXMEs and see if anything really important is left.
     Yu checked, they can wait until we merge the branch back.

### Things to do when merging back into the main branch

-[ ] Document the ALL option in l3 configs in the GitHub wiki.

-[ ] Address all remaining TODOs and FIXMEs.

-[ ] Clean up obsolete scripts anywhere

-[ ] Add a config file for each container name and config files and remove any hardcoded variable in any script.

-[ ] Clean up VPN scripts (as they are not tested)

-[ ] (Optional) Separate the config load part into separate scripts that can be merged with `layer2_config.sh` and `router_config.sh` later.