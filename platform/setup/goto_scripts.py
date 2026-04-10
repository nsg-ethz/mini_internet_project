from .config import *
from .subnet_config import *
from .helper import run_cmd

def goto_scripts(config: Topology, directory: Path):

    for group_no, domain in config.as_es.items():

        if isinstance(domain,AS):
            file_loc = f"{directory}/groups/g{group_no}/goto.sh"
            goto_content = ""

            goto_content += '#!/bin/bash\n'
            goto_content += 'location=${1,,}\n'  # ,, converts to lowercase
            goto_content += 'device=${2:-router}\n'
            goto_content += 'device=${device,,}\n'  # ,, converts to lowercase
            goto_content += '\n'


            for router_name, router in domain.routers.items():

                for i, _ in enumerate(router.hosts):

                    subnet_host = subnet_sshContainer_groupContainer(group_no, router.id + i, -1,  "L3-host")

                    host_name = f"host{i}" if len(router.services) > 1 else "host"
                    goto_content += f'if [ \"${{location}}" == \"{router_name.lower()}\" ] && [ \"${{device}}" == \"{host_name}\" ]; then\n'
                    goto_content += f'  subnet={subnet_host}\n'
                    goto_content += '  exec ssh -t -o StrictHostKeyChecking=no root@"${subnet%???}"\n'
                    goto_content += 'fi\n'

                subnet_router = subnet_sshContainer_groupContainer(group_no, router.id, -1, "router")

                # SSH to router container with vtysh
                goto_content += f'if [ \"${{location}}" == \"{router_name.lower()}\" ] && [ \"${{device}}" == \"router" ]; then\n'
                goto_content += f'  subnet={subnet_router}\n'
                goto_content += '  exec ssh -t -o StrictHostKeyChecking=no root@"${subnet%???}" vtysh\n'
                goto_content += 'fi\n'

                if router.access == Access.LINUX:
                    # SSH to router container with bash
                    goto_content += f'if [ \"${{location}}" == \"{router_name.lower()}\" ] && [ \"${{device}}" == \"container" ]; then\n'
                    goto_content += f'  subnet={subnet_router}\n'
                    goto_content += '  exec ssh -t -o StrictHostKeyChecking=no root@"${subnet%???}" bash\n'
                    goto_content += 'fi\n'
                
            for _, l2_network in domain.l2_networks.items():

                for switch in l2_network.switches.values():
                    subnet_switch = subnet_sshContainer_groupContainer(group_no, -1, switch.bridge_id-1, "switch")

                    goto_content += f'if [ \"${{location}}" == \"{l2_network.name.lower()}\" ] && [ \"${{device}}" == \"{switch.name.lower()}\" ]; then\n'
                    goto_content += f'  subnet={subnet_switch}\n'
                    goto_content += '  exec ssh -t -o StrictHostKeyChecking=no root@"${subnet%???}"\n'
                    goto_content += 'fi\n'


            for _, l2_network in domain.l2_networks.items():

                for host_name, l2_host in l2_network.hosts.items():

                    subnet_l2_host=subnet_sshContainer_groupContainer(group_no, 0, l2_host.l2_id,"L2-host")

                    goto_content += f'if [ \"${{location}}\" == \"{l2_network.name.lower()}\" ] && [ \"${{device}}\" == \"{host_name.lower()}\" ]; then\n'
                    goto_content += f'  subnet={subnet_l2_host}\n'
                    goto_content += '  exec ssh -t -o StrictHostKeyChecking=no root@\"${subnet%???}\"\n'
                    goto_content += 'fi\n'
            
            subnet_measurement = subnet_sshContainer_groupContainer(group_no, -1, -1, "MEASUREMENT")

            goto_content += 'if [ \"${location}\" == \"measurement\" ] && [ \"${device}\" == \"router\" ]; then\n'
            goto_content += f'  subnet={subnet_measurement}\n'
            goto_content += '  exec ssh -t -o StrictHostKeyChecking=no root@\"${subnet%???}\"\n'
            goto_content += 'fi\n'
            goto_content += '\n'
            goto_content += 'echo \"invalid arguments"\n'
            goto_content += 'echo \"valid examples:"\n'

            rname = next(iter(domain.routers)).lower()

            goto_content += f'echo \"./goto.sh {rname}"\n'
            goto_content += f'echo \"./goto.sh {rname} router"\n'
            goto_content += f'echo \"./goto.sh {rname} host"\n'
            
            if len(domain.l2_networks) > 0:
                l2_name = next(iter(domain.l2_networks))
                l2_host_name = next(iter(domain.l2_networks[l2_name].hosts))
                l2_switch_name = list(domain.l2_networks[l2_name].switches.values())[0].name
                goto_content += f'echo \"./goto.sh {l2_name.lower()} {l2_switch_name.lower()}\"\n'
                goto_content += f'echo \"./goto.sh {l2_name.lower()} {l2_host_name.lower()}\"\n'

            goto_content += 'echo \"./goto.sh measurement"\n'

            with open(file_loc,"w+") as file:
                file.write(goto_content)
            
            run_cmd(f"chmod 0755 {file_loc}")

