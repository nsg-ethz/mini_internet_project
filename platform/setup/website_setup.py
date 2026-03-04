from .config import *
from config.subnet_config import *
from .helper import run_cmd
import docker
import docker.types


def website_setup(config: Topology, directory: Path):

    client = docker.from_env()

    datadir = f"{directory}/groups"
    confdir = f"{directory}/config"
    run_cmd(f"mkdir -p {datadir}/webserver")
    conf_file = f"{datadir}/webserver/config.py"
    letsencrypt = f"{datadir}/webserver/letsencrypt"
    datadir_server = f"/server/data"
    configdir_server = f"/server/configs"
    env = config.environment

    tlsconf: list[str] = []
    if env["WEBSERVER_ACME_MAIL"] != "" and env["WEBSERVER_HOSTNAME"] != "" and env["WEBSERVER_HOSTNAME"] != "localhost":
        tlsconf += ["--entrypoints.web.http.redirections.entrypoint.to=websecure",
                   "--entrypoints.web.http.redirections.entrypoint.scheme=https",
                   "--entrypoints.web.http.redirections.entrypoint.permanent=true",
                   "--certificatesresolvers.project_resolver.acme.tlschallenge=true",
                   f"--certificatesresolvers.project_resolver.acme.email={env["WEBSERVER_ACME_MAIL"]}",
                   "--certificatesresolvers.project_resolver.acme.storage=/letsencrypt/acme.json",
                   "--entrypoints.websecure.http.tls.certresolver=project_resolver",
                   "--entrypoints.krill.http.tls.certresolver=project_resolver"]
        krill_scheme="https"
    else:
        krill_scheme="http"


    with open(conf_file, "w") as file:
        file.write("LOCATIONS = {\n")
        file.write(f"\"config_directory\": \"{configdir_server}\",\n")
        file.write(f"'as_config': \"{configdir_server}/AS_config.txt\",\n")
        file.write(f"\"as_connections_public\": \"{configdir_server}/aslevel_links_students.txt\",\n")
        file.write(f"\"as_connections\": \"{configdir_server}/aslevel_links.txt\",\n")
        file.write(f"'groups': '{datadir_server}',\n")
        file.write(f"\"matrix\": \"{datadir_server}/matrix/connectivity.txt\",\n")
        file.write(f"\"matrix_stats\": \"{datadir_server}/matrix/stats.txt\",\n")
        file.write(f"\"vpn_folder\": \"wireguard\",\n")
        file.write(f"\"vpn_passwd\": \"{datadir_server}/{env["VPN_PASSWD_FILE"]}\",\n")
        file.write(f"\"vpn_db\":\"{datadir_server}/webserver/{env["VPN_DB_FILE"]}\",\n")
        file.write(f"\"topology_txt\":\"{configdir_server}/topology.txt\",\n")
        file.write(f"\"topology_json\":\"/server/routing_project_server/static/topology.json\"\n")
        file.write("}\n")
        file.write(f"KRILL_URL=\"{krill_scheme}://{{hostname}}:{env["WEBSERVER_PORT_KRILL"]}/index.html\"\n")
        file.write(f"BASIC_AUTH_USERNAME = 'admin'\n")
        file.write(f"BASIC_AUTH_PASSWORD = 'admin'\n")
        file.write(f"BACKGROUND_WORKERS = True\n")
        file.write(f"HOST = '0.0.0.0'\n")
        file.write(f"PORT = 8000\n")
        file.write(f"VPN_ENABLED = {env["VPN_WEBSITE_ENABLED"].capitalize()}\n")
        file.write(f"VPN_NO_CLIENTS = {env["VPN_NO_CLIENTS"]}\n")
        file.write(f"TOPOLOGY_TAB = {env["TOPOLOGY_TAB"].capitalize()}\n")
        file.write(f"CHATBOT_INTEGRATION = {env["CHATBOT_INTEGRATION"].capitalize()}\n")
        file.write(f"CHATBOT_URL = \"{env["CHATBOT_URL"]}\"\n")



    webserver_label =  {"traefik.enable": "true", "traefik.http.routers.web.entrypoints": "web",
                       "traefik.http.routers.websecure.entrypoints": "websecure"}
    
    webserver_volumes = {"/var/run/docker.sock": {"bind": "/var/run/docker.sock", "mode": "rw"},
                        f"{datadir}": {"bind": f"{datadir_server}", "mode": "rw"},
                        f"{confdir}": {"bind": f"{configdir_server}", "mode": "rw"},
                        f"{conf_file}": {"bind": "/server/config.py", "mode": "rw"},
                        f"{confdir}{env["WEBSERVER_SOURCEFILES"]}": {"bind":"/server", "mode": "rw"}}
    
    #webserver_mount = [docker.types.Mount(target="/server", source=f"{confdir}{env["WEBSERVER_SOURCEFILES"]}", type="bind")]
    
    webserver_env = ["SERVER_CONFIG=/server/config.py",f"TZ={env["WEBSERVER_TZ"]}"]

    
    
    client.containers.run(image=f"{env["DOCKERHUB_PREFIX"]}webserver:{env["DOCKER_TAG"]}",
                          privileged=True, hostname="web", name="WEB", network="bridge", tty=True, detach=True,
                          ports={"8000": 8000}, pids_limit=100, cpu_count=2, environment=webserver_env,
                          volumes=webserver_volumes, labels=webserver_label)
    
    proxy_ports: dict[str, int] = {f"{env["WEBSERVER_PORT_HTTP"]}": int(env["WEBSERVER_PORT_HTTP"]),
                   f"{env["WEBSERVER_PORT_HTTPS"]}":  int(env["WEBSERVER_PORT_HTTPS"]),
                   f"{env["WEBSERVER_PORT_KRILL"]}":  int(env["WEBSERVER_PORT_KRILL"])}

    traefik_label = ["--providers.docker=True",
                     "--providers.docker.network=bridge",
                     "--providers.docker.exposedbydefault=false",
                     f"--providers.docker.defaultRule=Host(\\\"{env["WEBSERVER_HOSTNAME"]}\\\")",
                     f"--entrypoints.web.address=:{env["WEBSERVER_PORT_HTTP"]}",
                     f"--entrypoints.websecure.address=:{env["WEBSERVER_PORT_HTTPS"]}",
                     f"--entrypoints.krill.address=:{env["WEBSERVER_PORT_KRILL"]}"]

    traefik_volumes = {"/var/run/docker.sock": {"bind": "/var/run/docker.sock", "mode": "ro"},
                      f"{letsencrypt}": {"bind": "/letsencrypt", "mode": "rw"}}

    client.containers.run(image=f"traefik:v3.6.7",
                          privileged=True, name="PROXY", network="bridge", volumes=traefik_volumes,
                          ports=proxy_ports, pids_limit=100, cpu_count=2, detach=True,
                          command=" ".join(traefik_label+tlsconf))
