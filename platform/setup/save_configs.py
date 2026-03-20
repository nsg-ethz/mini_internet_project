from .config import *
from config.subnet_config import *
from .helper import run_cmd

def save_configs(config: Topology, directory: Path):

    for group_no, domain in config.as_es.items():
        
        #TODO fix environment variable
        SSH_URL = config.environment["SSH_URL"]

        folder = f"{directory}/groups/g{group_no}"
        save_file = f"{folder}/save_configs.sh"
        restore_file = f"{folder}/restore_configs.sh"
        ospfd_file = f"{folder}/restart_ospfd.sh"
        save_content = ""
        restore_content = ""
        
        if isinstance(domain,AS):
            
            # copy restart_ospfd from setup folder
            with open(f"{directory}/setup/restart_ospfd.sh") as source_file:
                with open(ospfd_file, "w+") as destination_file:
                    destination_file.write(source_file.read())
                    run_cmd(f"chmod 0755 {ospfd_file}")

            save_content += "#!/bin/bash\n"
            save_content += "\n" 
            save_content += "dirname=configs_${1:-$(date +%m-%d-%Y_%H-%M-%S)}\n"
            save_content += "mkdir -p $dirname\n"
            save_content += "\n"
            save_content += "# Arguments: filename, subnet, command\n"
            save_content += "save() { eval \"ssh -q -o StrictHostKeyChecking=no root@${2%???} ${@:3} > $1\" ; }\n"
            save_content += "\n"

            for router_name, router in domain.routers.items():

                savedir="${dirname}/"+f"{router_name}"
                subnet_router = subnet_sshContainer_groupContainer(group_no, router.id, -1, "router")

                save_content += f"echo {router_name} router\n"
                save_content += f"mkdir -p {savedir}\n"
                save_content += f"save {savedir}/router.conf      {subnet_router} \\\"vtysh -c \\\'sh run\\\'\\\"\n"
                save_content += f"save {savedir}/router.rib.json  {subnet_router} \\\"vtysh -c \\\'sh ip route json\\\'\\\"\n"
                if router.access == Access.LINUX:
                    # If we have linux access, we may also configure tunnels, so store that output."
                    # Add tunnels and ipv6 routes."
                    save_content += f"save {savedir}/router.rib6.json {subnet_router} \\\"vtysh -c \\\'sh ipv6 route json\\\'\\\"\n"
                    save_content += f"save {savedir}/router.rib6 {subnet_router} ip -6 route save\n"
                    save_content += f"save {savedir}/router.tunnels   {subnet_router} ip tunnel show\n"

                for i, host in enumerate(router.hosts):

                    subnet_host = subnet_sshContainer_groupContainer(group_no, router.id + i, -1,  "L3-host")

                    host_name = f"host{i}" if len(router.services) > 1 else "host"

                    save_content += f"echo {router_name} {host_name}\n"
                    save_content += f"save {savedir}/{host_name}.ip         {subnet_host} ip addr\n"
                    save_content += f"save {savedir}/{host_name}.route      {subnet_host} ip route\n"
                    save_content += f"save {savedir}/{host_name}.route6     {subnet_host} ip -6 route\n"

                    if host.type == HostType.KRILL or host.type == HostType.ROUTINATOR:
                        save_content += f"save {savedir}/{host_name}.rpki_cache {subnet_host} \"tar -czC /root/.rpki-cache repository\"\n"
                

            for _, l2_network in domain.l2_networks.items():

                for switch in l2_network.switches:
                    subnet=subnet_sshContainer_groupContainer(group_no, 0, switch.bridge_id-1 ,"switch")
                    save_dir = f"${{dirname}}/{switch.name}"

                    save_content += f"echo {switch.name}\n"
                    save_content += f"mkdir -p {save_dir}\n"
                    save_content += f"save {save_dir}/switch.db      {subnet} \"ovsdb-client backup\"\n"
                    save_content += f"save {save_dir}/switch.summary {subnet} \"ovs-vsctl show\"\n"

            for _, l2_network in domain.l2_networks.items():
                for host_name, l2_host in l2_network.hosts.items():
                    subnet=subnet_sshContainer_groupContainer(group_no, 0, l2_host.l2_id,"L2-host")
                    save_dir=f"${{dirname}}/{host_name}"

                    save_content += f"echo {host_name}\n"
                    save_content += f"mkdir -p {save_dir}\n"
                    save_content += f"save {save_dir}/host.ip     {subnet} \"ip addr\"\n"
                    save_content += f"save {save_dir}/host.route  {subnet} \"ip route\"\n"
                    save_content += f"save {save_dir}/host.route6 {subnet} \"ip -6 route\"\n"
            
            save_content += "cp ~/secret.txt ${dirname}/secret.txt\n"
            save_content += "\n"
            save_content += "tar -czf ${dirname}.tar.gz ${dirname}/*\n"
            save_content += "\n"
            save_content += "echo \'Saving complete!\'\n"
            save_content += "echo \'\'\n"
            save_content += "echo \"Download the archive file (run these commands from your own computer):\"\n"
            save_content += f"echo \"    scp -O -P {2000 + group_no} root@{SSH_URL}:${{dirname}}.tar.gz .\"\n"
            save_content += "echo \'Extract the archive:\'\n"
            save_content += "echo \"    tar -xzf ${dirname}.tar.gz\"\n"
            save_content += "echo \"Alternatively, to directly update the \"config\" folder in the current local directory:\"\n"
            save_content += f"echo \"    scp -O -r -P {2000 + group_no} root@{SSH_URL}:${{dirname}} config\"\n"
            save_content += "echo \'\'\n"
            save_content += "echo \'If the scp commands do not work for you, use ssh (also from your own computer):\'\n"
            save_content += "echo \'(Reliable only on UNIX systems. On Windows, you may use WinSCP instead)\'\n"
            save_content += "echo \"Download the archive:\"\n"
            save_content += f"echo \"    ssh -q -p {2000 + group_no} root@{SSH_URL} cat ${{dirname}}.tar.gz > ${{dirname}}.tar.gz\"\n"
            save_content += "echo \"Download and unpack the archive:\"\n"
            save_content += f"echo \"    ssh -q -p {2000 + group_no} root@{SSH_URL} cat ${{dirname}}.tar.gz | tar -xz\"\n"
            save_content += "echo \'\'\n"
            save_content += "echo \'If you are using an ssh config file, you may need to update the scp and ssh commands above to match your configuration.\'\n"
            save_content += f"echo \'For example, you may need to replace \"root@{SSH_URL}\" with the hostname you have defined in your ssh config file.\'\n"
            save_content += "echo \'Contact the TAs if you are unable to download your files!\'\n"

            with open(save_file, "w+") as f:
                f.write(save_content)
                run_cmd(f"chmod 0755 {save_file}")
    

            restore_content += "#!/bin/bash\n"
            restore_content += "\n"
            restore_content += "configs_folder_name=$1\n"
            restore_content += "\n"
            restore_content += "if [ ! -d \"$configs_folder_name\" ]; then\n"
            restore_content += "echo \"$configs_folder_name does not work.\"\n"
            restore_content += "echo \"Please make sure your path points to the top folder containing the extracted config files.\"\n"
            restore_content += "exit 1\n"
            restore_content += "fi\n"
            restore_content += "# Arguments: subnet, command\n"
            restore_content += "restore() { echo \"root@${1%???} ${@:2}\"; eval \"ssh -q -o StrictHostKeyChecking=no root@${1%???} ${@:2}\" ; }\n"
            restore_content += "copy() { echo \"root@${1%???} $2 $3\"; eval \"scp -q -o StrictHostKeyChecking=no $2 root@${1%???}:$3\" ;}\n"
            restore_content += "echo \" \n \n \" \n"
            restore_content += "\n"


            for router_name, router in domain.routers.items():

                savedir="${dirname}/"+f"{router_name}"
                subnet_router = subnet_sshContainer_groupContainer(group_no, router.id, -1, "router")

                restore_content += f"echo \" \n \n Restoring {router_name} router configuration... \n \" \n"
                restore_content += f"copy {subnet_router} $configs_folder_name/{router_name}/router.conf /root/frr.conf\n"
                restore_content += f"restore {subnet_router} sed -i '1,3d' /root/frr.conf \n"
                restore_content += f"restore {subnet_router} /usr/lib/frr/frr-reload.py --reload /root/frr.conf\n"
                restore_content += f"restore {subnet_router} rm /root/frr.conf\n"

                if router.access == Access.LINUX:
                    restore_content += f"tunnel_name=$(cat ${{configs_folder_name}}/{router_name}/router.tunnels | grep -v sit0 | awk '{{sub(\":\", \"\", $1); print $1}}')\n"
                    restore_content += f"tunnel_remote=$(cat ${{configs_folder_name}}/{router_name}/router.tunnels | grep -v sit0 | awk '{{print $4}}')\n"
                    restore_content += f"tunnel_local=$(cat ${{configs_folder_name}}/{router_name}/router.tunnels | grep -v sit0 | awk '{{print $6}}')\n"
                    restore_content += "add_tunnel_cmd=$(echo \"ip tunnel add $tunnel_name mode sit remote $tunnel_remote local $tunnel_local ttl 255\")\n"
                    restore_content += f"restore {subnet_router} $add_tunnel_cmd\n"
                    restore_content += f"restore {subnet_router} ip link set $tunnel_name up\n"
                    restore_content += f"copy {subnet_router} ${{configs_folder_name}}/{router_name}/router.rib6 router.rib6\n"
                    restore_content += f"restore {subnet_router} \"ip -6 route restore \\< router.rib6\"\n"

                
                for i, host in enumerate(router.hosts):
                    
                    subnet_host = subnet_sshContainer_groupContainer(group_no, router.id + i, -1,  "L3-host")

                    host_name = f"host{i}" if len(router.services) > 1 else "host"

                    restore_content += f"echo \" \n \n Restoring {router_name} host configuration... \n \" \n"
                    # Get the IPv4 address
                    restore_content += f"ipv4=$(cat ${{configs_folder_name}}/{router_name}/{host_name}.ip | grep -w inet | grep {router_name}router | awk '{{print $2}}')\n"
                    # Get the IPv6 address
                    restore_content += f"ipv6=$(cat ${{configs_folder_name}}/{router_name}/{host_name}.ip | grep -w inet6 | grep {router_name}router | awk '{{print $2}}')\n"
                    # Get default route (IPv4 only?)
                    restore_content += f"default_route=$(cat ${{configs_folder_name}}/{router_name}/{host_name}.route | grep -w default | awk '{{print $3}}')\n"
                    restore_content += f"restore {subnet_host} ip addr flush dev {router_name}router\n"
                    restore_content += f"restore {subnet_host} ip route flush dev {router_name}router\n"
                    restore_content += f"restore {subnet_host} ip -6 route flush dev {router_name}router\n"
                    # Adding the IPv4 and IPv6 address
                    restore_content += f"restore {subnet_host} ip address add ${{ipv4}} dev {router_name}router\n"
                    restore_content += f"restore {subnet_host} ip route add default via ${{default_route}}\n"
            
            for _, l2_network in domain.l2_networks.items():

                for switch in l2_network.switches:
                    subnet=subnet_sshContainer_groupContainer(group_no, 0, switch.bridge_id-1 ,"switch")
                    save_dir = f"${{dirname}}/{switch.name}"

                    restore_content += f"echo \" \n \n Restoring {switch.name} configuration... \n \"\n"
                    restore_content += f"copy {subnet} $configs_folder_name/{switch.name}/switch.db /root/switch.db\n"
                    restore_content += f"restore {subnet} \"ovsdb-client restore \\< /root/switch.db \" \n"
                    restore_content += "sleep 2\n"
                    restore_content += f"restore {subnet} rm /root/switch.db\n"
                        
            for _, l2_network in domain.l2_networks.items():
                for host_name, l2_host in l2_network.hosts.items():
                    subnet=subnet_sshContainer_groupContainer(group_no, 0, l2_host.l2_id,"L2-host")
                    save_dir=f"${{dirname}}//{host_name}"

                    #TODO find better way to do this
                    link = [link for link in l2_network.links if host_name in link.endpoints][0].endpoints
                    switch_name = link[0] if link[1] == host_name else link[1]

                    restore_content += f"echo \" \n \n Restoring {host_name} configuration...  \n \" \n"
                    # Get the IPv4 address
                    restore_content += f"ipv4=$(cat ${{configs_folder_name}}/{host_name}/host.ip | grep -w inet | grep {group_no}-{switch_name} | awk '{{print $2}}')\n"
                    restore_content += f"echo \"Backuped {host_name} IPv4: ${{ipv4}}\"\n"
                    # Get the IPv6 address
                    restore_content += f"ipv6=$(cat ${{configs_folder_name}}/{host_name}/host.ip | grep -w inet6 | grep global | awk '{{print $2}}')\n"
                    restore_content += f"echo \"Backuped {host_name} IPv6: ${{ipv6}}\"\n"
                    # Get default route (IPv4 only?)
                    restore_content += f"default_route=$(cat ${{configs_folder_name}}/{host_name}/host.route | grep -w default | awk '{{print $3}}')\n"
                    restore_content += f"echo \"Backuped {host_name} Default IPv4 Route: ${{default_route}}\"\n"
                    # Get default route IPv6
                    restore_content += f"default_route_v6=$(cat ${{configs_folder_name}}/{host_name}/host.route6 | grep -w default | awk '{{print $3}}')\n"
                    restore_content += f"echo \"Backuped {host_name} Default IPv6 Route: ${{default_route_v6}}\"\n"
                    restore_content += f"restore {subnet} ip addr flush dev {group_no}-{switch_name}\n"
                    restore_content += f"restore {subnet} ip route flush dev {group_no}-{switch_name}\n"
                    restore_content += f"restore {subnet} ip -6 route flush dev {group_no}-{switch_name}\n"
                    restore_content += f"restore {subnet} ip address add ${{ipv4}} dev {group_no}-{switch_name}\n"
                    restore_content += f"restore {subnet} ip address add ${{ipv6}} dev {group_no}-{switch_name}\n"
                    restore_content += f"restore {subnet} ip route add default via ${{default_route}}\n"
                    restore_content += f"restore {subnet} ip route add default via ${{default_route_v6}}\n"
            restore_content += f"cp $configs_folder_name/secret.txt ~/secret.txt"

            with open(restore_file, "w+") as f:
                f.write(restore_content)
                run_cmd(f"chmod 0755 {restore_file}")

