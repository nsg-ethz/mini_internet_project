from .config import *
from config.subnet_config import *
from .helper import run_cmd
from subprocess import CalledProcessError
import os
import docker
import time



def vpn_config(config: Topology, directory: Path):

    #TODO fix getting evironment variables
    os.environ["VPN_ENABLED"] = config.environment.get("VPN_ENABLED", "true")
    os.environ["VPN_NO_CLIENTS"] = config.environment.get("VPN_NO_CLIENTS", "1")
    os.environ["VPN_LIMIT_ENABLED"] = config.environment.get("VPN_LIMIT_ENABLED", "true")
    os.environ["VPN_LIMIT_RATE"] = config.environment.get("VPN_LIMIT_RATE", "1mbit")
    os.environ["VPN_LIMIT_BURST"] = config.environment.get("VPN_LIMIT_BURST", "32kbit")
    os.environ["VPN_LIMIT_LATENCY"] = config.environment.get("VPN_LIMIT_LATENCY", "40ms")
    os.environ["VPN_DNS_ENABLED"] = config.environment.get("VPN_DNS_ENABLED","true")
    os.environ["SSH_URL"] = config.environment.get("SSH_URL", "localhost")

    VPN_ENABLED = bool(os.environ["VPN_ENABLED"])

    if VPN_ENABLED == False:
        print("VPN not enabled, skipping VPN setup")

    try:
        run_cmd("command -v wg",check=True)
    except CalledProcessError:
        print("WireGuard is not installed. Please install WireGuard.")
        return
    print("WireGuard is installed. Proceeding.")
    
    for group_no, domain in config.as_es.items():
        create_vpn(directory, group_no, domain)


def check_intf_exists(interface_file: Path):
    return os.path.exists(interface_file)

def create_if(directory: Path, group_no: int, router_name: str, router_id: int, interface_ip: str):

    interface_file = Path(f"{directory}/groups/g{group_no}/{router_name}/wireguard/interface.conf")
    pubkey_file = Path(f"{directory}/groups/g{group_no}/{router_name}/wireguard/interface.pubkey")

    if (check_intf_exists(interface_file)):
        print("Error: A wireguard interface already exists!")
        return
    
    private_key = str(run_cmd("wg genkey").stdout)
    public_key = str(run_cmd(f"echo \"{private_key}\" | wg pubkey").stdout)
    listen_port = 10000 + group_no + 1000 * router_id

    with open(interface_file,"w+") as file:
        file.write(f"[Interface]\nPrivateKey={private_key}\nListenPort={listen_port}\n\n")
    with open(pubkey_file,"w+") as file:
        file.write(public_key)
    
    client = docker.from_env()
    container = client.containers.get(f"{group_no}_{router_name}router")
    api = docker.APIClient(base_url='unix://var/run/docker.sock')
    pid = api.inspect_container(container.id)["State"]["Pid"]

    run_cmd("ip link add vpn type wireguard")
    run_cmd(f"ip link set vpn netns {pid}")
    run_cmd(f"nsenter --net=/proc/{pid}/ns/net ip address add {interface_ip} dev vpn")

    container.exec_run("wg setconf vpn /etc/wireguard/interface.conf",user="root")

    time.sleep(0.1)
    run_cmd(f"nsenter --net=/proc/{pid}/ns/net ip link set vpn up")

    # Set up rate limits
    if bool(os.environ["VPN_LIMIT_ENABLED"]):
        VPN_LIMIT_RATE = os.environ["VPN_LIMIT_RATE"]
        VPN_LIMIT_BURST = os.environ["VPN_LIMIT_BURST"]
        VPN_LIMIT_LATENCY = os.environ["VPN_LIMIT_LATENCY"]
        run_cmd(f"nsenter --net=/proc/{pid}/ns/net tc qdisc add dev vpn root tbf rate {VPN_LIMIT_RATE} burst {VPN_LIMIT_BURST} latency {VPN_LIMIT_LATENCY}")

	# Set firewall exception
    run_cmd(f"ufw allow {listen_port}")


def create_wg_peer(directory: Path, group_no: int, router_name: str, router_id: int, peer_name: str, peer_ip: str):
    
    interface_file = Path(f"{directory}/groups/g{group_no}/{router_name}/wireguard/interface.conf")
    peer_file = Path(f"{directory}/groups/g{group_no}/{router_name}/wireguard/{peer_name}.peer")
    pubkey_file = Path(f"{directory}/groups/g{group_no}/{router_name}/wireguard/interface.pubkey")

    if check_intf_exists(peer_file):
        print(f"Peer ${peer_name} already exists! ({group_no}-{router_name})")
        return

    private_key = str(run_cmd("wg genkey").stdout)
    public_key = str(run_cmd(f"echo \"{private_key}\" | wg pubkey").stdout)
    listen_port = 10000 + group_no + 1000 * router_id
    dns = f"198.{group_no}.0.2"
    wg_subnet = "0.0.0.0/0"

    client = docker.from_env()
    container = client.containers.get(f"{group_no}_{router_name}router")
    container.exec_run(f"wg set vpn peer {public_key} persistent-keepalive 25 allowed-ips {peer_ip}",user="root")

    with open(interface_file,"a+") as file:
        file.write(f"[Peer]\nPublicKey={public_key}\nAllowedIPs={peer_ip}\nPersistentKeepalive=25\n\n")

    with open(peer_file,"w+") as file:
        file.write(f"[Interface]\nPrivateKey={private_key}\nAddress={peer_ip}\n")
        
        if bool(os.environ["VPN_DNS_ENABLED"]):
            file.write(f"DNS={dns}\n")
        
        with open(pubkey_file) as pubkey:
            server_pubkey = pubkey.read()
            file.write(f"\n[Peer]\nPublicKey={server_pubkey}\nAllowedIPs={wg_subnet}\nEndpoint={os.environ["SSH_URL"]}:{listen_port}\nPersistentKeepalive=25\n\n")
    

        


def create_vpn(directory: Path, group_no: int, domain: Domain):
    
    if isinstance(domain, AS):
        docker_client = docker.from_env()
        for router_name, router in domain.routers.items():
            interface_ip = subnet_host_router(group_no, router.id, "vpn_interface")

            create_if(directory, group_no, router_name, router.id, interface_ip)

            for client_no in range(1, int(os.environ["VPN_NO_CLIENTS"]) + 1):
                peer_ip=subnet_host_router(group_no, router.id, "vpn_peer", n_vpn_peer=client_no)
                peer_name=f"Client{client_no}"

                create_wg_peer(directory, group_no, router_name, router.id, peer_name, peer_ip)

                container = docker_client.containers.get(f"{group_no}_{router_name}router")
                container.exec_run(f"vtysh -c \"conf t\" -c \"router ospf\" -c \"network {interface_ip} area 0\"")


