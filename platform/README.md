# The mini-Internet platform

The documentation is available in the [**wiki**](https://github.com/nsg-ethz/mini_internet_project/wiki).

### 2024 Routing project (25 March!)

-[x] Fix the website/krill unreachable issue.

-[ ] Finish and test the new restart script for each containers.

-[ ] Check and test the automatic matrix snapshot and config backup.
     Alex: make it a container/service instead so its easier to use!

-[ ] Design this year's topology (Africa).

-[ ] Adjust and test the configuration for the new topology using the same tasks as last year.

-[ ] Adjust the matrix based on Laurent's feedback.
     Allow to disable validity checking.
     Alex: Need to update webserver, not matrix.

-[ ] Adjust the wiki based on Romain and Laurent's feedback

    - [ ] mention `advertised-route` in the wiki
    - [ ] more on community list semantics
    - [ ] adjust command examples ,e.g., `neighbor 11.11.11.11`

-[x] Contact sysadmin to open ports.

-[ ] Launch a medium-sized topology and contact student TAs to solve it.

-[ ] Generate student Gitlab repositories.

-[ ] Search for all FIXME and TODOs and address them.

-[x] Test launch traceroute and the matrix. I'm not sure I understand the matrix updates.

-[x] Test goto commands, also in stub and tier1.

-[ ] Is the examples folder of any use nowadays? Maybe just remove it.

-[x] Can I get from one ssh proxy to another via the network? Or ping others via the ssh proxy?
     I think this is working as intended.

-[ ] Test restarting any container.

-[ ] Document the ALL option in l3 configs.

-[ ] Plenty of scripts in /groups are not used anymore. Are they still created? check that.

-[x] Uncomment hijack.

-[ ] VPN?

-[x] Add ./go-to MEASUREMENT?

-[x] Create a MEASUREMENT Welcome message.

-[ ] Collect all variables in one file for easier config.

-[ ] Add new matrix flags.

-[ ] Ask student TAs to check: downloading configs, L2 stuff, 6in4 tunnel, goto scripts, dns output.
