from .config import *
from config.subnet_config import *
from .helper import run_cmd
import docker 
from ipaddress import IPv4Interface

def rpki_config(config: Topology, directory: Path, password_file: Path, keep_password: bool = False):


    
    rpki_location=f"{directory}/groups/rpki"
    run_cmd(f"mkdir -p {rpki_location}/tals")

    EXPIRES_IN_DAYS=365
    ISSUER="/C=CH/L=Zurich/O=ETH Zurich"
    run_cmd(f"openssl req -new -x509 -newkey rsa:4096 -sha256 -nodes -keyout \"{rpki_location}/root.key\" \
             -out \"{rpki_location}/root.crt\" -days \"{EXPIRES_IN_DAYS}\" -subj \"{ISSUER}\"")

    if keep_password and password_file.is_file():
            run_cmd(f"cp {password_file} {directory}/groups/passwords.txt")
    else:
        for group_no, domain in config.as_es.items():
            passwd = str(run_cmd("openssl rand -hex 8").stdout)
            with open(f"{directory}/groups/passwords.txt","a+") as file:
                file.write(f"{group_no} {passwd}")
    

    run_cmd(f"ssh-keygen -t rsa -b 4096 -C \"krill webserver\" -P \"\" -f {directory}/groups/rpki/id_rsa_krill_webserver -q")

    for role in ["readonly", "admin"]:
        passwd = str(run_cmd("openssl rand -hex 8").stdout)
        with open(f"{directory}/groups/krill_passwords.txt","a+") as file:
            file.write(f"{role} {passwd}")

    for group_no, domain in config.as_es.items():

        if isinstance(domain,AS):

            for router_name, router in domain.routers.items():

                for i, host in enumerate(router.hosts):

                    if host.type == HostType.ROUTINATOR:

                        subnet = str(IPv4Interface(subnet_host_router(group_no, router.id + i, "host")).ip)

                        with open(f"{directory}/groups/g{group_no}/routinator.txt","a+") as file:
                            file.write(f"{subnet}")

                        with open(f"{directory}/groups/g{group_no}/rpki_exceptions.json","a+") as file:
                            file.write("{\n")
                            file.write("  \"slurmVersion\": 1,\n")
                            file.write("  \"validationOutputFilters\": {\n")
                            file.write("    \"prefixFilters\": [],\n")
                            file.write("    \"bgpsecFilters\": []\n")
                            file.write("  },\n")
                            file.write("  \"locallyAddedAssertions\": {\n")
                            file.write("    \"prefixAssertions\": [],\n")
                            file.write("    \"bgpsecAssertions\": []\n")
                            file.write("  }\n")
                            file.write("}\n")
                        
                        with open(f"{directory}/groups/g{group_no}/rpki_exceptions_autograder.json","a+") as file:
                            file.write("{\n")
                            file.write("  \"slurmVersion\": 1,\n")
                            file.write("  \"validationOutputFilters\": {\n")
                            file.write("    \"prefixFilters\": [],\n")
                            file.write("    \"bgpsecFilters\": []\n")
                            file.write("  },\n")
                            file.write("  \"locallyAddedAssertions\": {\n")
                            file.write("    \"prefixAssertions\": [ \n")
                            for as_no in range(1, 254):
                                file.write("    { \n")
                                file.write("      \"asn\": 10000, \n")
                                file.write(f"      \"prefix\": \"200.{as_no}.0.0/16\", \n")
                                file.write("      \"maxPrefixLength\": 16, \n")
                                file.write("      \"comment\": \"used by the autograder container\" \n")
                                file.write("    }, \n")

                            file.write("    { \n")
                            file.write("      \"asn\": 10000, \n")
                            file.write("      \"prefix\": \"200.254.0.0/16\", \n")
                            file.write("      \"maxPrefixLength\": 16, \n")
                            file.write("      \"comment\": \"used by the autograder container\" \n")
                            file.write("    } \n")
                            file.write("  ],\n")
                            file.write("    \"bgpsecAssertions\": []\n")
                            file.write("  }\n")
                            file.write("}\n")
                    
                    elif host.type == HostType.KRILL:

                        subnet = str(IPv4Interface(subnet_host_router(group_no, i, "host")).ip)

                        krill_subject = f"/C=CH/L=Zurich/O=ETH Zurich/CN=rpki-server.group{group_no}"
                        krill_san = f"DNS:rpki-server.group{group_no}, DNS:rpki-server.group{group_no}:3000,\
                                    DNS:rpki-server.group{group_no}:3080, DNS:host.{router_name}.group{group_no},\
                                    DNS:localhost, IP:{subnet}, IP:127.0.0.1"
                        krill_group_location = f"{directory}/groups/g{group_no}/krill"

                        run_cmd(f"mkdir -p {krill_group_location}/data")

                        krill_cert_extension_file=f"{krill_group_location}/krill.ext"

                        with open(krill_cert_extension_file,"a+") as file:
                            file.write("[krill]\n")
                            file.write(f"subjectAltName={krill_san}\n")
                            file.write("basicConstraints=CA:FALSE\n")

                        run_cmd(f"openssl req -new -newkey rsa:4096 -keyout \"{krill_group_location}/krill.key\" \
                                -out \"{krill_group_location}/krill.csr\" -sha256 -nodes -subj \"{krill_subject}\"")

                        run_cmd(f"openssl x509 -in \"{krill_group_location}/krill.csr\" -req \
                                -out \"{krill_group_location}/krill.crt\" -CA \"{rpki_location}/root.crt\" \
                                -CAkey \"{rpki_location}/root.key\" -CAcreateserial -extensions krill \
                                -extfile \"{krill_cert_extension_file}\" -days \"{EXPIRES_IN_DAYS}\"")
                        

                        run_cmd(f"cat \"{krill_group_location}/krill.crt\" \"{krill_group_location}/krill.key\" > \"{krill_group_location}/krill.includesprivatekey.pem\"")


                        setup_location = f"{krill_group_location}/setup.sh"
                        krill_config_location = f"{krill_group_location}/krill.conf"
                        krill_auth_token_location = f"{krill_group_location}/krill_token.txt"

                        with open(setup_location,"a+") as file:
                            file.write("#!/bin/bash -e\n")
                            file.write("export KRILL_TEST=true\n")
                            file.write("KRILL_SERVER=\"https://127.0.0.1:3000/\"\n")
                        
                        krill_auth_token = str(run_cmd("uuidgen").stdout).strip()

                        with open(krill_auth_token_location,"a+") as file:
                            file.write(krill_auth_token)

                        with open(krill_config_location,"a+") as file:
                            file.write("# General configuration for krill\n")
                            file.write("ip           = \"127.0.0.1\"\n")
                            file.write("port         = 3001\n")
                            file.write("data_dir     = \"/var/krill/data/\"\n")
                            file.write("pid_file     = \"/var/run/krill.pid\"\n")
                            file.write("repo_enabled = true\n")
                            file.write("log_type     = \"stderr\"\n")
                            file.write(f"rsync_base   = \"rsync://rpki-server.group{group_no}:3000/repo/\"\n")
                            file.write(f"service_uri  = \"https://rpki-server.group{group_no}:3000/\"\n")
                            file.write(f"auth_token   = \"{krill_auth_token}\"\n")
                            file.write("bgp_risdumps_enabled = false\n")
                            file.write("timing_roa_valid_weeks = 2\n")
                            file.write("timing_roa_reissue_weeks_before = 1\n")
                            file.write("# Multi-user configuration for krill\n")
                            file.write("auth_type    = \"config-file\"\n")
                            file.write("[testbed]\n")
                            file.write(f"rrdp_base_uri = \"https://rpki-server.group{group_no}:3000/rrdp/\"\n")
                            file.write(f"rsync_jail = \"rsync://rpki-server.group{group_no}:3000/repo/\"\n")
                            file.write(f"ta_aia = \"rsync://rpki-server.group{group_no}:3000/ta/ta.cer\"\n")
                            file.write(f"ta_uri = \"https://rpki-server.group{group_no}:3000/ta/ta.cer\"\n")
                            file.write("[auth_users]\n")
                        

                        for other_group_no, domain_2 in config.as_es.items():
                            
                            ca_name=f"group{other_group_no}"
                            other_group_subnet=subnet_group(other_group_no)

                            if isinstance(domain_2, AS):

                                with open(setup_location,"a+") as file:
                                    file.write(f"krillc add --server $KRILL_SERVER --ca \"{ca_name}\"\n")                               
                                    # Register CA with local publication server                            
                                    file.write(f"krillc repo request --server $KRILL_SERVER \\\n")                               
                                    file.write(f"    --ca \"{ca_name}\" > /tmp/{ca_name}_publisher_request.xml\n")                               
                                    file.write("krillc pubserver publishers add \\\n")                               
                                    file.write("    --server $KRILL_SERVER \\\n")                               
                                    file.write(f"    --publisher \"{ca_name}\" \\\n")                               
                                    file.write(f"    --request /tmp/{ca_name}_publisher_request.xml > /tmp/{ca_name}_repository_response.xml\n")                               
                                    file.write("krillc repo configure --server $KRILL_SERVER \\\n")                               
                                    file.write(f"    --ca \"{ca_name}\" \\\n")                               
                                    file.write("    --format text \\\n")                               
                                    file.write(f"    --response /tmp/{ca_name}_repository_response.xml\n")                               
                                    # Add TA as parent of CA (CA RFC 8183 Child Request XML file)                              
                                    file.write("krillc parents request --server $KRILL_SERVER \\\n")                               
                                    file.write(f"    --ca \"{ca_name}\" > /tmp/{ca_name}_myid.xml\n")                               
                                    # As TA: add CA as child using the request file                              
                                    file.write("krillc children add --server $KRILL_SERVER \\\n")                               
                                    file.write("    --ca ta \\\n")                               
                                    file.write(f"    --child \"{ca_name}\" \\\n")                               
                                    file.write(f"    --asn \"AS{other_group_no}\" \\\n")
                                    file.write(f"    --ipv4 \"{other_group_subnet}\" \\\n")                               
                                    file.write(f"    --request /tmp/{ca_name}_myid.xml > /tmp/{ca_name}_parent_response.xml\n")                               
                                    # As CA: add TA as parent using the response file                              
                                    file.write("krillc parents add --server $KRILL_SERVER \\\n")                               
                                    file.write(f"    --ca \"{ca_name}\" \\\n")
                                    file.write("    --parent ta \\\n")                               
                                    file.write(f"    --response /tmp/{ca_name}_parent_response.xml\n")                               
                          
                                

