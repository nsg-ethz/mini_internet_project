import subprocess



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