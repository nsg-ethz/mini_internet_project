import subprocess
import docker
import time
from pathlib import Path

def run_cmd(cmd: str | list[str], check: bool = True) -> subprocess.CompletedProcess[str]:
    """Run a shell command and return the result.
    
    Args:
        cmd: Command as a string or list of arguments.
        check: If True, raise CalledProcessError on non-zero exit.
    
    Returns:
        CompletedProcess with stdout/stderr captured.
    
    Examples:
        run_cmd("sysctl net.ipv4.neigh.default.gc_thresh1=16384")
        run_cmd(["sysctl", "-w", "net.ipv4.ip_forward=1"])
    """
    if isinstance(cmd, str):
        return subprocess.run(cmd, shell=True, check=check, capture_output=True, text=True)
    return subprocess.run(cmd, check=check, capture_output=True, text=True)

def get_num_threads() -> int:
    n_cores=str(run_cmd("grep -c ^processor /proc/cpuinfo").stdout)
    n_threads_per_core=str(run_cmd("lscpu | grep -E \'^Thread\\(s\\) per core:\' | awk \'{print $4}\'").stdout)
    return int(n_cores) * int(n_threads_per_core)

def compute_burstsize(thrp: str):

    suffix = {"": 1, "k": 10**3, "m": 10**6, "g": 10**9, "t": 10**12,
              "ki": 1024, "mi": 1024**2, "gi": 1024**3, "ti": 1024**4}
    
    # 10 times MTU in bits
    min_burst = 1500 * 80

    tail = thrp.lstrip('0123456789')
    bits = int(thrp[:-len(tail)])

    if "bps" in tail:
        bits *= 8
    suffix_unit = tail.replace("bps","").replace("bit","")

    if suffix_unit in suffix.keys():
        unit = suffix[suffix_unit]
    else:
        print("not a valid throughput unit for links, set to 80 * 1500 bits")
        return  min_burst
    

    burst = 0.1 * bits * unit

    if burst < min_burst:
        burst = min_burst
    
    return burst

def create_unique_port_name(identifier: str):

    ID=str(run_cmd(f"uuidgen -s --namespace @url --name {identifier} | sed 's/-//g'").stdout)
    return ID[0:13]

def create_netns_symlink(pid: int):
    if Path("/var/run/netns").exists() == False:
        run_cmd("mkdir -p /var/run/netns")
    
    if Path(f"/var/run/netns/{pid}").exists() == False:

        run_cmd(f"ln -s /proc/{pid}/ns/net /var/run/netns/{pid}")
        run_cmd("trap  \'delete_netns_symlink\' 0")

        for signal in [1, 2, 3, 13, 14, 15]:
            run_cmd(f"trap \'delete_netns_symlink; trap - $signal; kill -$signal $$\' {signal}")

def get_docker_pid(name: str):
    client = docker.from_env()
    api = docker.APIClient(base_url='unix://var/run/docker.sock')
    container_id_1 = client.containers.get(name).id
    client.close()
    return int(api.inspect_container(container_id_1)["State"]["Pid"])

def connect_two_interfaces(cont_1: str, intf_1: str, cont_2: str, intf_2: str, perf: None | tuple[str,str,str] = None) -> tuple[int, int]:

    pid_1 = get_docker_pid(cont_1)
    pid_2 = get_docker_pid(cont_2)
    
    if perf != None:
        thrp, delay, buffer = perf
        burst = compute_burstsize(thrp)

    portname = create_unique_port_name(f"{cont_1}_{intf_1}_{cont_2}_{intf_2}")
    veth_intf_1 = f"{portname}_a"
    veth_intf_2 = f"{portname}_b"

    create_netns_symlink(pid_1)
    create_netns_symlink(pid_2)

    run_cmd(f"ip link add {veth_intf_1} type veth peer name {veth_intf_2}")

    run_cmd(f"ip link set {veth_intf_1} netns {pid_1}")
    run_cmd(f"ip netns exec {pid_1} ip link set dev {veth_intf_1} name {intf_1}",check=False)
    run_cmd(f"ip netns exec {pid_1} ip link set {intf_1} up")

    run_cmd(f"ip link set {veth_intf_2} netns {pid_2}")
    run_cmd(f"ip netns exec {pid_2} ip link set dev {veth_intf_2} name {intf_2}")
    run_cmd(f"ip netns exec {pid_2} ip link set {intf_2} up")
    
    time.sleep(0.1)

    if perf != None:
        run_cmd(f"ip netns exec {pid_1} tc qdisc add dev {intf_1} root handle 1:0 netem delay {delay}")
        run_cmd(f"ip netns exec {pid_1} tc qdisc add dev {intf_1} parent 1:1 handle 10: tbf rate \"{thrp}\" burst {burst} latency \"{buffer}\"")

        run_cmd(f"ip netns exec {pid_2} tc qdisc add dev {intf_2} root handle 1:0 netem delay {delay}")
        run_cmd(f"ip netns exec {pid_2} tc qdisc add dev {intf_2} parent 1:1 handle 10: tbf rate \"{thrp}\" burst {burst} latency \"{buffer}\"")

    return (pid_1, pid_2)



def clean_ctn_netns(pid: int):
    run_cmd(f"ip netns del {pid} 2>/dev/null || true")
    run_cmd(f"rm -f /var/run/netns/{pid} 2>/dev/null || true")


def clean_ip_link():
    interfaces = str(run_cmd("ip link | grep -E '_b|_a|_h|_r' | awk -F': ' '{print $2}' | cut -d'@' -f1").stdout).split()

    for interface in interfaces:
        run_cmd(f"ip link delete {interface} || true")