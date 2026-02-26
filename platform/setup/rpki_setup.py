from .config import *
from config.subnet_config import *
from .helper import run_cmd
import docker
import time

def rpki_router_setup(config: Topology, directory: Path):

    for external_link in config.external_links:

        if isinstance(config.as_es[external_link.src[0]], IXP) or isinstance(config.as_es[external_link.dst[0]], IXP):

            if isinstance(config.as_es[external_link.src[0]], IXP):
                grp_1, router_grp_1 = external_link.dst
                grp_2, router_grp_2 = external_link.src
            else:
                grp_1, router_grp_1 = external_link.src
                grp_2, router_grp_2 = external_link.dst

            configdir=f"{directory}/groups/g{grp_1}/{router_grp_1}/config"
            with open(f"{configdir}/conf_rpki.sh","a+") as file:
                 # Set highest local preference where rpki validation returns a valid state
                file.write(f"route-map IXP_IN_{grp_2} permit 4\n")
                file.write(f"match rpki valid\n")
                file.write(f"set community {grp_1}:20\n")
                file.write(f"set local-preference 150\n")
                file.write(f"exit\n")
                # Drop all announcements where rpki validation returns an invalid state
                file.write(f"route-map IXP_IN_{grp_2} deny 8\n")
                file.write(f"match rpki invalid\n")
                file.write(f"exit\n")
                # All announcements where rpki validation returns notfound get
                # a lower local-preference.
                file.write(f"route-map IXP_IN_{grp_2} permit 6\n")
                file.write(f"match rpki notfound\n")
                file.write(f"set community {grp_1}:20\n")
                file.write(f"set local-preference 40\n")
                file.write(f"exit\n")

        else:

            grp_1, router_grp_1 = external_link.src
            grp_2, router_grp_2 = external_link.dst

            configdir=f"{directory}/groups/g{grp_1}/{router_grp_1}/config"
            with open(f"{configdir}/conf_rpki.sh","a+") as file:

                file.write(f"route-map LOCAL_PREF_IN_{grp_2} permit 4\n")
                file.write(f"match rpki valid\n")
                           
                if external_link.relationship == Relationship.PROV_CUST:
                    file.write(f"set community {grp_1}:10\n")
                    file.write(f"set local-preference 200\n")
                elif external_link.relationship == Relationship.PEER:
                    file.write(f"set community {grp_1}:20\n")
                    file.write(f"set local-preference 150\n")
                
                file.write(f"exit\n")
                file.write(f"route-map LOCAL_PREF_IN_{grp_2} deny 8\n")
                file.write(f"match rpki invalid\n")
                file.write(f"exit\n")
                
                file.write(f"route-map LOCAL_PREF_IN_{grp_2} permit 6\n")
                file.write(f"match rpki notfound\n")
                
                if external_link.relationship == Relationship.PROV_CUST:
                    file.write(f"set community {grp_1}:10\n")
                    file.write(f"set local-preference 90\n")
                elif external_link.relationship == Relationship.PEER:
                    file.write(f"set community {grp_1}:20\n")
                    file.write(f"set local-preference 40\n")
                
                file.write(f"exit\n")


            configdir=f"{directory}/groups/g{grp_2}/{router_grp_2}/config"
            with open(f"{configdir}/conf_rpki.sh","a+") as file:

                file.write(f"route-map LOCAL_PREF_IN_{grp_1} permit 4\n")
                file.write(f"match rpki valid\n")
                           
                if external_link.relationship == Relationship.PROV_CUST:
                    file.write(f"set community {grp_2}:30\n")
                    file.write(f"set local-preference 120\n")
                elif external_link.relationship == Relationship.PEER:
                    file.write(f"set community {grp_2}:20\n")
                    file.write(f"set local-preference 150\n")
                
                file.write(f"exit\n")
                file.write(f"route-map LOCAL_PREF_IN_{grp_1} deny 8\n")
                file.write(f"match rpki invalid\n")
                file.write(f"exit\n")
                
                file.write(f"route-map LOCAL_PREF_IN_{grp_1} permit 6\n")
                file.write(f"match rpki notfound\n")
                
                if external_link.relationship == Relationship.PROV_CUST:
                    file.write(f"set community {grp_2}:30\n")
                    file.write(f"set local-preference 10\n")
                elif external_link.relationship == Relationship.PEER:
                    file.write(f"set community {grp_2}:20\n")
                    file.write(f"set local-preference 40\n")
                
                file.write(f"exit\n")

    

    for group_no, domain in config.as_es.items():

        if isinstance(domain, AS):
           
            for router_name, router in domain.routers.items():
                
                if domain.auto:

                    location = f"{directory}/groups/g{group_no}/{router_name}/config/conf_rpki.sh"
                    with open(f"{directory}/groups/g{group_no}/routinator.txt") as file:
                        routinator_ips = [line.strip() for line in file.readlines()]
                    
                    if len(routinator_ips) == 0:
                       print(f"WARN: Group {group_no} has no routinator instance! Skip RPKI router configuration.")
                    else:
                        run_cmd(f"docker cp \"{location}\" \"{group_no}_{router_name}router\":/home/conf_rpki.conf > /dev/null")
                        run_cmd(f"docker exec -d \"{group_no}_{router_name}router\" /home/conf_rpki.conf &")

    


def krill_setup(config: Topology, directory: Path):

    client = docker.from_env()

    krill_containers: list[tuple[int,str]] = []
    routinator_containers: list[tuple[int,str]] = []

    for group_no, domain in config.as_es.items():

        if isinstance(domain, AS):
            for router in domain.routers.values():
                for i, host in enumerate(router.hosts):
                    extra = f"{i}" if len(router.services) > 1 else ""
                    hostl3_cnt_name=f"{group_no}_{router.name}host{extra}"

                    if host.type == HostType.KRILL:
                        krill_containers += [(group_no, hostl3_cnt_name)]

                    if host.type == HostType.ROUTINATOR:
                        routinator_containers += [(group_no, hostl3_cnt_name)]    
    
    for as_no, krill_cnt in krill_containers:
                        
        with open(f"groups/rpki/id_rsa_krill_webserver.pub") as file:
            pubkey = file.read()
            client.containers.get(f"{as_no}_ssh").exec_run(f"bash -c \"echo \'restrict,port-forwarding,command=\\\"/bin/false\\\" {pubkey}\' >> ~/.ssh/authorized_keys\"")

        client.containers.get(krill_cnt).exec_run(f"/bin/bash /home/setup.sh")
        time.sleep(5)
        client.containers.get(krill_cnt).exec_run(f"bash -c \"wget -q -O /var/krill/tals/group{as_no}.tal https://127.0.0.1:3000/ta/ta.tal \"")

    for as_no, routinator_cnt in routinator_containers:
        run_cmd(f"docker exec {routinator_cnt} bash -c \"kill -1 \\$(cat /var/run/routinator.pid)\"")
            

    for as_no, krill_cnt in krill_containers:

        admin_passwd= str(run_cmd(f"awk \"\\$1 == \\\"admin\\\" {{ print \\$0 }}\" \"{directory}/groups/krill_passwords.txt\" | cut -f 2 -d \' \'").stdout)
        readonly_passwd = str(run_cmd(f"awk \"\\$1 == \\\"readonly\\\" {{ print \\$0 }}\" \"{directory}/groups/krill_passwords.txt\" | cut -f 2 -d \' \'").stdout)

        output = str(run_cmd(f"echo \"{admin_passwd}\" | docker exec -i {krill_cnt} krillc config user --id \"admin@ethz.ch\" -a \"role=admin\" | grep \"admin\" | tr -d \'\\r\'").stdout) + "\n"
        output += str(run_cmd(f"echo \"{readonly_passwd}\" | docker exec -i {krill_cnt} krillc config user --id \"readonly@ethz.ch\" -a \"role=readonly\" | grep \"readonly\" | tr -d \'\\r\'").stdout) + "\n"
        
        krill_config_location=f"{directory}/groups/g{as_no}/krill/krill.conf"
        with open(krill_config_location,"a") as file:
            file.write(output)
            

    for group_no, domain in config.as_es.items():

        if isinstance(domain,AS):


            for as_no, krill_cnt in krill_containers:

                krill_group_location = f"{directory}/groups/g{as_no}/krill"
                krill_config_location = f"{krill_group_location}/krill.conf"

                passwd = str(run_cmd(f"awk \" \\$1 == {group_no}{{ print \\$0 }}\" \"{directory}/groups/passwords.txt\" | cut -f 2 -d \' \'").stdout)

                with open(krill_config_location,"a+") as file:
                    file.write(str(run_cmd(f"echo \"{passwd}\" | docker exec -i {krill_cnt} krillc config user --id \"group{group_no}@ethz.ch\" -a \"role=readwrite\" -a \"inc_cas=group{group_no}\" | grep \"group{group_no}\" | tr -d \'\\r\'").stdout))

                if domain.auto:
                    group_subnet = subnet_group(group_no)
                    

                    print(f"group {group_no}: Adding default ROA \"{group_subnet} => {group_no}\"...")

                    while "State: active" not in str(run_cmd(f"docker exec {krill_cnt} krillc show --ca \"group{group_no}\"").stdout):
                        time.sleep(1)
                    
                    run_cmd(f"docker exec {krill_cnt} krillc roas update --ca \"group{group_no}\" --add \"{group_subnet} => {group_no}\"")
                    print(f"group {group_no}: Default ROA added.")

                # Apply ROA delta file if available for the group
                if Path(f"{directory}/config/roas/g{group_no}.txt").exists():
                     run_cmd(f"docker exec {krill_cnt} krillc roas update --ca \"group{group_no}\" --delta \"/var/krill/roas/g{group_no}.txt\"")

            for router_name, router in domain.routers.items():
                with open(f"{directory}/groups/g{group_no}/routinator.txt") as file:
                    routinator_ips = [line.strip() for line in file.readlines()]

                with open(f"{directory}/groups/g{group_no}/{router_name}/config/conf_rpki.sh","a+") as file:
                    file.write("#!/usr/bin/vtysh -f\n")
                    file.write("rpki\n")
                    file.write("rpki reset\n")
                    file.write("rpki polling_period 60\n")
                    for j, ip in enumerate(routinator_ips):
                        file.write(f"rpki cache tcp {ip} 3323 pref {j+1}\n")
                    file.write("exit\n")
                run_cmd(f"chmod +x {directory}/groups/g{group_no}/{router_name}/config/conf_rpki.sh")
    

    # Restart all krill daemons
    for as_no, krill_cnt in krill_containers:
        run_cmd(f"docker exec {krill_cnt} bash -c \"kill -3 \\$(cat /var/run/krill.pid)\"")



    
            

def rpki_setup(config: Topology, directory: Path):

    krill_setup(config, directory)
    rpki_router_setup(config,directory)
    