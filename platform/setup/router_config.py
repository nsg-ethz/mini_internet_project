from .config import *
from config.subnet_config import *
from .helper import get_num_threads, run_cmd, get_docker_pid
from multiprocessing import Pool
from ipaddress import IPv4Interface, IPv6Interface
import docker
import time

def router_config_group(config: Topology, group_no: int, domain: Domain, directory: Path):

    if isinstance(domain,AS):

        for router_name, router in domain.routers.items():

            configdir=f"{directory}/groups/g{group_no}/{router_name}/config"
            # Create files and directoryu
            run_cmd(f"mkdir -p {configdir}")
            with open(f"{configdir}/conf_init.sh","a+") as file:
                file.write("#!/usr/bin/vtysh -f\n")
            run_cmd(f"chmod +x {configdir}/conf_init.sh")

            with open(f"{configdir}/conf_full.sh","a+") as file:
                router_subnet = subnet_router(group_no, router.id)
                file.write("#!/usr/bin/vtysh -f\n")
                file.write("interface lo\n")
                file.write(f"ip address {router_subnet}\n")
                file.write(f"exit\n")

                for i, host in enumerate(router.hosts):
                    host_subnet = subnet_host_router(group_no, router.id + i, "router") 
                    extra = f"{i}" if len(router.services) > 1 else ""
                    file.write(f"interface host{extra}\n")
                    file.write(f"ip address {host_subnet}\n")
                    file.write("exit\n")
                    file.write("router ospf\n")
                    file.write(f"network {host_subnet} area 0\n")
                    file.write("exit\n")
                
                for i, l2_network in enumerate(domain.l2_networks.values()):
                    for switch in l2_network.switches:
                        if switch.router == router_name:
                            l2_subnet_router = subnet_l2_router(group_no, i)
                            file.write(f"router ospf\n")
                            file.write(f"network {l2_subnet_router} area 0\n")
                            file.write("exit\n")


                router_id=IPv4Interface(subnet_router(group_no, router.id))
                group_subnet = subnet_group(group_no)

                file.write("router ospf\n")
                file.write(f"ospf router-id {str(router_id.ip)}\n")
                file.write(f"network {router_id.with_prefixlen} area 0\n")
                file.write("exit\n")
                file.write(f"ip route {group_subnet} null0\n")
                file.write(f"ip prefix-list OWN_PREFIX seq 5 permit {group_subnet}\n")
                file.write(f"route-map OWN_PREFIX permit 10\n")
                file.write("match ip address prefix-list OWN_PREFIX\n")
                file.write("exit\n")

                for router_2 in domain.routers.values():
                    if router_2.name != router.name:
                        ip_router = str(IPv4Interface(subnet_router(group_no,router_2.id)).ip)
                        
                        file.write(f"router bgp {group_no}\n")
                        file.write(f"network {group_subnet}\n")
                        file.write(f"neighbor {ip_router} remote-as {group_no}\n")
                        file.write(f"neighbor {ip_router} update-source lo\n")
                        file.write(f"neighbor {ip_router} next-hop-self\n")
                        file.write(f"exit\n")
            

            run_cmd(f"chmod +x {configdir}/conf_full.sh")

        for i, link in enumerate(domain.internal_links):
            router_1 = link.endpoints[0]
            router_2 = link.endpoints[1]
            with open(f"{directory}/groups/g{group_no}/{router_1}/config/conf_full.sh","a") as file:
                subnet_intern = subnet_router_router_intern(group_no, i, "1")
                file.write(f"interface port_{router_2}\n")
                file.write(f"ip address {subnet_intern}\n")
                file.write(f"ip ospf cost 1\n")
                file.write(f"exit\n")
                file.write(f"router ospf\n")
                file.write(f"network {subnet_intern} area 0\n")
                file.write(f"exit\n")
            with open(f"{directory}/groups/g{group_no}/{router_2}/config/conf_full.sh","a") as file:
                subnet_intern = subnet_router_router_intern(group_no, i, "2")
                file.write(f"interface port_{router_1}\n")
                file.write(f"ip address {subnet_intern}\n")
                file.write(f"ip ospf cost 1\n")
                file.write(f"exit\n")
                file.write(f"router ospf\n")
                file.write(f"network {subnet_intern} area 0\n")
                file.write(f"exit\n")     

    elif isinstance(domain,IXP):

        configdir=f"{directory}/groups/g{group_no}/config"
        # Create files and directoryu
        run_cmd(f"mkdir -p {configdir}")
        with open(f"{configdir}/conf_init.sh","a+") as file:
            file.write("#!/usr/bin/vtysh -f\n")
        run_cmd(f"chmod +x {configdir}/conf_init.sh")


        with open(f"{configdir}/conf_full.sh","a+") as file:
            file.write("#!/usr/bin/vtysh -f\n")
            for external_link in config.external_links:

                if external_link.src[0] == group_no or external_link.dst[0] == group_no:

                    if external_link.src[0] == group_no:
                        grp_1, router_grp_1 = external_link.dst
                        grp_2, router_grp_2 = external_link.src
                    else:
                        grp_1, router_grp_1 = external_link.src
                        grp_2, router_grp_2 = external_link.dst

                    subnet_1 = str(IPv4Interface(subnet_router_IXP(grp_1, grp_2, "group")).ip)

                    file.write(f"bgp community-list {grp_1} permit {grp_2}:{grp_1}\n")
                    file.write(f"route-map {grp_1}_EXPORT permit 10\n")
                    file.write(f"match community {grp_1}\n")
                    file.write(f"exit\n")
                    file.write(f"route-map {grp_1}_IMPORT permit 10\n")
                    file.write(f"exit\n")
                    file.write(f"router bgp {grp_2}\n")
                    file.write(f"bgp router-id 180.{grp_2}.0.{grp_2}\n")
                    file.write(f"neighbor {subnet_1} remote-as {grp_1}\n")
                    file.write(f"neighbor {subnet_1} activate\n")
                    file.write(f"neighbor {subnet_1} route-server-client\n")
                    file.write(f"neighbor {subnet_1} route-map {grp_1}_IMPORT in\n")
                    file.write(f"neighbor {subnet_1} route-map {grp_1}_EXPORT out\n")
                    file.write(f"exit\n")

                    run_cmd(f"docker exec -d {group_no}_IXP bash -c \"ovs-vsctl add-port IXP grp_{grp_1}\"\n")

        run_cmd(f"chmod +x {configdir}/conf_full.sh")


def services_config(group_no: int, domain: Domain, directory: Path):

    if isinstance(domain, AS):

        for router_name, router in domain.routers.items():

            configdir=f"{directory}/groups/g{group_no}/{router_name}/config"

            if Service.MEASUREMENT in router.services:
                subnet_meas = subnet_router_MEASUREMENT(group_no, "group")
                with open(f"{configdir}/conf_init.sh","a+") as file:
                    file.write(f"interface measurement_{group_no}\n")
                    file.write(f"ip address {subnet_meas}\n")
                    file.write(f"exit\n")
                    file.write(f"router ospf\n")
                    file.write(f"network {subnet_meas} area 0\n")
                    file.write(f"exit\n")

            if Service.MATRIX in router.services:
                subnet_meas = subnet_router_MATRIX(group_no, "group")
                with open(f"{configdir}/conf_init.sh","a+") as file:
                    file.write(f"interface matrix_{group_no}\n")
                    file.write(f"ip address {subnet_meas}\n")
                    file.write(f"exit\n")
                    file.write(f"router ospf\n")
                    file.write(f"network {subnet_meas} area 0\n")
                    file.write(f"exit\n")
            
            if Service.DNS in router.services:
                subnet_meas = subnet_router_DNS(group_no, "group")
                with open(f"{configdir}/conf_init.sh","a+") as file:
                    file.write(f"interface dns_{group_no}\n")
                    file.write(f"ip address {subnet_meas}\n")
                    file.write(f"exit\n")
                    file.write(f"router ospf\n")
                    file.write(f"network {subnet_meas} area 0\n")
                    file.write(f"exit\n")


def apply_config(group_no: int, domain: Domain, directory: Path):

    if isinstance(domain, AS):

        for router_name, router in domain.routers.items():

            config_dir=f"{directory}/groups/g{group_no}/{router_name}/config"

            run_cmd(f"docker cp {config_dir}/conf_init.sh {group_no}_{router_name}router:/home/conf_init.sh > /dev/null")
            run_cmd(f"docker exec -d {group_no}_{router_name}router /home/conf_init.sh &")

            if domain.auto:
                run_cmd(f"docker cp {config_dir}/conf_full.sh {group_no}_{router_name}router:/home/conf_full.sh > /dev/null")
                run_cmd(f"docker exec -d {group_no}_{router_name}router /home/conf_full.sh &")

    else:
        config_dir=f"{directory}/groups/g{group_no}/config"
        run_cmd(f"docker cp {config_dir}/conf_full.sh {group_no}_IXP:/conf_full.sh > /dev/null")

        run_cmd(f"docker exec -d {group_no}_IXP /conf_full.sh &")
        run_cmd(f"docker exec -d {group_no}_IXP bash -c \"ifconfig IXP 180.{group_no}.0.{group_no}/24\" &")



def config_external_links(config: Topology, directory: Path):
    for external_link in config.external_links:

        if isinstance(config.as_es[external_link.src[0]], IXP) or isinstance(config.as_es[external_link.dst[0]], IXP):

            if isinstance(config.as_es[external_link.src[0]], IXP):
                grp_1, router_grp_1 = external_link.dst
                grp_2, router_grp_2 = external_link.src
            else:
                grp_1, router_grp_1 = external_link.src
                grp_2, router_grp_2 = external_link.dst
            
            str_temp = " ".join([f"{grp_2}:{value}" for value in external_link.community_values])
            subnet_1 = subnet_router_IXP(grp_1, grp_2, "group")
            subnet_2 = str(IPv4Interface(subnet_router_IXP(grp_1, grp_2, "IXP")).ip)
            group_subnet = subnet_group(grp_1)

            configdir=f"{directory}/groups/g{grp_1}/{router_grp_1}/config"
            with open(f"{configdir}/conf_full.sh","a+") as file:
                
                file.write(f"interface ixp_{grp_2}\n")
                file.write(f"ip address {subnet_1}\n")
                file.write(f"exit\n")
                file.write(f"router bgp {grp_1}\n")
                file.write(f"network {group_subnet}\n")
                file.write(f"neighbor {subnet_2} remote-as {grp_2}\n")
                file.write(f"neighbor {subnet_2} activate\n")
                file.write(f"neighbor {subnet_2} route-map IXP_OUT_{grp_2} out\n")
                file.write(f"neighbor {subnet_2} route-map IXP_IN_{grp_2} in\n")
                # The IXP does not add it's own AS to the AS_PATH which causes member routers to drop routes from the IXP
                file.write(f"no neighbor {subnet_2} enforce-first-as\n")
                file.write(f"exit\n")

                file.write(f"bgp community-list 1 permit {grp_1}:10\n")
                file.write(f"route-map IXP_OUT_{grp_2} permit 10\n")
                file.write(f"set community {str_temp}\n")
                file.write(f"match ip address prefix-list OWN_PREFIX\n")
                file.write(f"exit\n")
                file.write(f"route-map IXP_OUT_{grp_2} permit 20\n")
                file.write(f"set community {str_temp}\n")
                file.write(f"match community 1\n")
                file.write(f"exit\n")
                file.write(f"route-map IXP_IN_{grp_2} permit 10\n")
                file.write(f"set community {grp_1}:20\n")
                file.write(f"set local-preference 50\n")
                file.write(f"exit\n")

        else:
            grp_1, router_grp_1 = external_link.src
            grp_2, router_grp_2 = external_link.dst
            
            subnet = external_link.subnet.network

            sub_1 = IPv4Interface(f"{subnet.network_address + grp_1}/{subnet.prefixlen}")
            sub_2 = IPv4Interface(f"{subnet.network_address + grp_2}/{subnet.prefixlen}")

            configdir=f"{directory}/groups/g{grp_1}/{router_grp_1}/config"
            group_subnet = subnet_group(grp_1)
            with open(f"{configdir}/conf_full.sh","a+") as file:
                file.write(f"interface ext_{grp_2}_{router_grp_2}\n")
                file.write(f"ip address {sub_1.with_prefixlen}\n")
                file.write(f"exit\n")
                file.write(f"router bgp {grp_1}\n")
                file.write(f"neighbor {sub_2.ip} remote-as {grp_2}\n")
                file.write(f"neighbor {sub_2.ip} route-map LOCAL_PREF_IN_{grp_2} in\n")
                file.write(f"neighbor {sub_2.ip} route-map LOCAL_PREF_OUT_{grp_2} out\n")
                file.write(f"network {group_subnet}\n")
                file.write(f"exit\n")

                if external_link.relationship == Relationship.PROV_CUST:

                    file.write(f"bgp community-list 2 permit {grp_1}:10\n")
                    file.write(f"bgp community-list 2 permit {grp_1}:20\n")
                    file.write(f"bgp community-list 2 permit {grp_1}:30\n")
                    file.write(f"route-map LOCAL_PREF_IN_{grp_2} permit 10\n")
                    file.write(f"set community {grp_1}:10\n")
                    file.write(f"set local-preference 100\n")
                    file.write(f"exit\n")
                    file.write(f"route-map LOCAL_PREF_OUT_{grp_2} permit 5\n")
                    file.write(f"match ip address prefix-list OWN_PREFIX\n")
                    file.write(f"exit\n")
                    file.write(f"route-map LOCAL_PREF_OUT_{grp_2} permit 10\n")
                    file.write(f"match community 2\n")
                    file.write(f"exit\n")

                elif external_link.relationship == Relationship.PEER:

                    file.write(f"bgp community-list 1 permit {grp_1}:10\n")
                    file.write(f"route-map LOCAL_PREF_IN_{grp_2} permit 10\n")
                    file.write(f"set community {grp_1}:20\n")
                    file.write(f"set local-preference 50\n")
                    file.write(f"exit\n")
                    file.write(f"route-map LOCAL_PREF_OUT_{grp_2} permit 5\n")
                    file.write(f"match ip address prefix-list OWN_PREFIX\n")
                    file.write(f"exit\n")
                    file.write(f"route-map LOCAL_PREF_OUT_{grp_2} permit 10\n")
                    file.write(f"match community 1\n")
                    file.write(f"exit\n")

            configdir=f"{directory}/groups/g{grp_2}/{router_grp_2}/config"
            group_subnet = subnet_group(grp_2)
            with open(f"{configdir}/conf_full.sh","a+") as file:

                file.write(f"interface ext_{grp_1}_{router_grp_1}\n")
                file.write(f"ip address {sub_2.with_prefixlen}\n")
                file.write(f"exit\n")
                file.write(f"router bgp {grp_2}\n")
                file.write(f"neighbor {sub_1.ip} remote-as {grp_1}\n")
                file.write(f"neighbor {sub_1.ip} route-map LOCAL_PREF_IN_{grp_1} in\n")
                file.write(f"neighbor {sub_1.ip} route-map LOCAL_PREF_OUT_{grp_1} out\n")
                file.write(f"network {group_subnet}\n")
                file.write(f"exit\n")

                if external_link.relationship == Relationship.PROV_CUST:

                    file.write(f"bgp community-list 1 permit {grp_2}:10\n")
                    file.write(f"route-map LOCAL_PREF_IN_{grp_1} permit 10\n")
                    file.write(f"set community {grp_2}:20\n")
                    file.write(f"set local-preference 50\n")
                    file.write(f"exit\n")
                    file.write(f"route-map LOCAL_PREF_OUT_{grp_1} permit 5\n")
                    file.write(f"match ip address prefix-list OWN_PREFIX\n")
                    file.write(f"exit\n")
                    file.write(f"route-map LOCAL_PREF_OUT_{grp_1} permit 10\n")
                    file.write(f"match community 1\n")
                    file.write(f"exit\n")

                elif external_link.relationship == Relationship.PEER:

                    file.write(f"bgp community-list 1 permit {grp_2}:10\n")
                    file.write(f"route-map LOCAL_PREF_IN_{grp_1} permit 10\n")
                    file.write(f"set community {grp_2}:20\n")
                    file.write(f"set local-preference 50\n")
                    file.write(f"exit\n")
                    file.write(f"route-map LOCAL_PREF_OUT_{grp_1} permit 5\n")
                    file.write(f"match ip address prefix-list OWN_PREFIX\n")
                    file.write(f"exit\n")
                    file.write(f"route-map LOCAL_PREF_OUT_{grp_1} permit 10\n")
                    file.write(f"match community 1\n")
                    file.write(f"exit\n")


def router_config(config: Topology, directory: Path):

    pool = Pool(processes = get_num_threads())
    inputs = [(config, group_no,domain, directory) for group_no, domain in config.as_es.items()]
    pool.starmap(router_config_group, inputs)

    config_external_links(config,directory)

    pool = Pool(processes = get_num_threads())
    inputs = [(group_no, domain, directory) for group_no, domain in config.as_es.items()]
    pool.starmap(services_config, inputs)

    print(f"Sleeping 2 seconds")
    time.sleep(2)

    pool = Pool(processes = get_num_threads())
    inputs = [(group_no, domain, directory) for group_no, domain in config.as_es.items()]
    pool.starmap(apply_config, inputs)
    
            
    



