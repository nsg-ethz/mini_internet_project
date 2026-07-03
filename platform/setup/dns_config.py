from .config import *
from .subnet_config import *
from .helper import run_cmd
from ipaddress import IPv4Interface



def forward_entry(forward_records:str, name: str, ip: str):
    with open(forward_records,"a+") as file:
        file.write(f"{name.lower()}. IN A {ip}\n")

def reverse_entry(reverse_records: str, name: str, ip:str):
    with open(reverse_records,"a+") as file:
        file.write(f"{".".join(ip.split(".")[:0:-1])} IN  PTR {name.lower()}.\n")



def dns_config(config: Topology, directory: Path):


    run_cmd(f"mkdir {directory}/groups/dns")
    run_cmd(f"mkdir {directory}/groups/dns/group_config")
    run_cmd(f"mkdir {directory}/groups/dns/zones")

    location_options = f"{directory}/groups/dns/named.conf.options"

    with open(location_options,"a+") as file:
        
        file.write("options {\n")
        file.write("    directory \"/var/cache/bind\";\n")
        file.write("\n")
        file.write("    recursion no;\n")
        file.write("    listen-on { ")
    
        for group_no, domain in config.as_es.items():

            dns_ip = str(IPv4Interface(subnet_router_DNS(group_no,"dns-group")).ip)

            file.write(f"{dns_ip}; ")

        ip_measurement = str(IPv4Interface(subnet_router_DNS(-1, "dns-measurement")).ip)

        file.write(f"{ip_measurement}; ")

        file.write("};\n")
        file.write("    allow-transfer { none; };\n")
        file.write("\n")
        file.write("    dnssec-validation auto; \n")
        file.write("    auth-nxdomain no;    # conform to RFC1035\n")
        file.write("};\n")

    
    for group_no, domain in config.as_es.items():

        location_local = f"{directory}/groups/dns/named.conf.local"
        forward_records = f"groups/dns/group_config/named.conf.local.group{group_no}"

        if isinstance(domain, AS):
            with open(location_local,"a+") as file:
                file.write(f"include \"/etc/bind/group_config/named.conf.local.group{group_no}\";\n")

            with open(forward_records,"a+") as file:

                file.write(f"zone \"group{group_no}\"" + " {\n")
                file.write(" type master;\n")
                file.write(f" file \"/etc/bind/zones/db.group{group_no}\";\n")
                file.write("};\n")
                file.write(f"zone \"{group_no}.in-addr.arpa\"" + " {\n")
                file.write(" type master;\n")
                file.write(f" file \"/etc/bind/zones/db.{group_no}\";\n")
                file.write("};\n")       

    for group_no, domain in config.as_es.items():
        
        domain_name=f"group{group_no}"

        # create zone definitions for both forward (db.group[number]
        # and reverse (db.[number) DNS records
        forward_records=f"groups/dns/zones/db.{domain_name}"
        reverse_records=f"groups/dns/zones/db.{group_no}"


        if isinstance(domain, AS):
            
            with open(reverse_records,"a+") as file:
                file.write(f";\n")
                file.write(f"; BIND reverse data file for local loopback interface\n")
                file.write(f";\n")
                file.write(f"$TTL    604800\n")
                file.write(f"@   IN  SOA ns.{domain_name}. ns.{domain_name}. (\n")
                file.write(f"                  {group_no}     ; Serial\n")
                file.write(f"             604800     ; Refresh\n")
                file.write(f"              86400     ; Retry\n")
                file.write(f"            2419200     ; Expire\n")
                file.write(f"             604800 )   ; Negative Cache TTL\n")
                file.write(f";\n")
                file.write(f"\n")
                file.write(f"    IN  NS  ns.{domain_name}.\n")
                file.write(f"\n")
                file.write(f"\n")
            
            with open(forward_records,"a+") as file:
                file.write(f";\n")
                file.write(f"; BIND data file for local loopback interface\n")
                file.write(f";\n")
                file.write(f"$TTL    604800\n")
                file.write(f"@       IN      SOA     ns.{domain_name}. admin.{domain_name}. (\n")
                file.write(f"                              {group_no}         ; Serial\n")
                file.write(f"                         604800         ; Refresh\n")
                file.write(f"                          86400         ; Retry\n")
                file.write(f"                        2419200         ; Expire\n")
                file.write(f"                         604800 )       ; Negative Cache TTL\n")
                file.write(f";\n")
                file.write(f"\n")
                file.write(f"        IN      NS      ns.{domain_name}.\n")
                file.write(f"\n")

            
            ip = str(IPv4Interface(subnet_router_DNS(group_no, "dns-group")).ip)

            forward_entry(forward_records,f"ns.group{group_no}",ip)

            for router_name, router in domain.routers.items():

                ip = str(IPv4Interface(subnet_router(group_no, router.id)).ip)
                forward_entry(forward_records, f"{router_name}.{domain_name}" ,ip)
                reverse_entry(reverse_records, f"{router_name}.{domain_name}" ,ip)

                for i, host in enumerate(router.hosts):

                    ip1 = str(IPv4Interface(subnet_host_router(group_no, router.id + i, "host")).ip)
                    ip2 = str(IPv4Interface(subnet_host_router(group_no, router.id + i, "router")).ip)

                    if host.type == HostType.KRILL:
                        forward_entry(forward_records,f"rpki-server.{domain_name}", ip1)
                    
                    forward_entry(forward_records, f"host.{router_name}.{domain_name}", ip1)
                    forward_entry(forward_records, f"{router_name}.{domain_name}", ip2)

                    reverse_entry(reverse_records, f"host.{router_name}.{domain_name}", ip1)
                    reverse_entry(reverse_records, f"{router_name}.{domain_name}", ip2)


                if Service.MEASUREMENT in router.services:
                    m_ip = str(IPv4Interface(subnet_router_MEASUREMENT(group_no, "group")).ip)
                    forward_entry(forward_records, f"measurement.{router_name}.{domain_name}", m_ip)
                    reverse_entry(reverse_records, f"measurement.{router_name}.{domain_name}", m_ip)

            
            for i, link in enumerate(domain.internal_links):
                router_list = list(domain.routers.keys())

                if link.endpoints[0] in router_list and link.endpoints[1] in router_list:
                    ip1 = str(IPv4Interface(subnet_router_router_intern(group_no, i, "1")).ip)
                    ip2 = str(IPv4Interface(subnet_router_router_intern(group_no, i, "2")).ip)

                    forward_entry(forward_records, f"{link.endpoints[0]}.{domain_name}", ip1)
                    forward_entry(forward_records, f"{link.endpoints[1]}.{domain_name}", ip2)

                    reverse_entry(reverse_records, f"{link.endpoints[0]}.{domain_name}", ip1)
                    reverse_entry(reverse_records, f"{link.endpoints[1]}.{domain_name}", ip2)








    

