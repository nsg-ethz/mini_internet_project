
def subnet_group(n_grp: int):
  return f"{n_grp}.0.0.0/8"


def subnet_host_router(n_grp: int, n_router: int, device: str, n_vpn_peer=1):
    if device == "host":
        return f"{n_grp}.{n_router + 101}.0.1/24"
    elif device == "router":
        return f"{n_grp}.{n_router + 101}.0.2/24"
    elif device == "bridge":
        return f"{n_grp}.{n_router + 101}.0.0/24"
    elif device == "vpn_interface":
        return f"{n_grp}.{n_router + 101}.10.1/24"
    elif device == "vpn_peer":
        return f"{n_grp}.{n_router + 100}.10.{1 + n_vpn_peer}/32"
    else:
        raise ValueError(f"subnet_host_router: unknown device {device}")

def subnet_l2_router(n_grp: int, l2_id: int):
    return f"{n_grp}.{200 + l2_id}.0.0/16"

def subnet_l2(n_grp: int, l2_id: int, vlan: int, n_host: int):
    return f"{n_grp}.{200 + l2_id}.{vlan}.{n_host}/24"

def gw_l2_(n_grp: int, vlan: int, n_host: int):
    return f"{n_grp}.200.{vlan}.{n_host}/24"

def subnet_l2_router_ipv6(n_grp: int, l2_id: int):
    return f"{n_grp}:{200 + l2_id}::/32"

def subnet_l2_ipv6(n_grp: int, l2_id: int, vlan: int, n_host: int):
    return f"{n_grp}:{200 + l2_id}:{vlan}::{n_host}/48"

def subnet_router(n_grp: int, n_router: int):
    return f"{n_grp}.{n_router + 151}.0.1/24"

def subnet_router_router_intern(n_grp: int, n_net: int, device: str):
    if device == "1":
        return f"{n_grp}.0.{n_net + 1}.1/24"
    elif device == "2":
        return f"{n_grp}.0.{n_net + 1}.2/24"
    elif device == "bridge":
        return f"{n_grp}.0.{n_net + 1}.0/24"
    else:
        raise ValueError(f"subnet_router_router_intern: unknown device {device}")

def subnet_router_router_extern(n_net: int, device: str):
    mod = n_net % 100
    div = n_net // 100
    
    if device == "1":
        return f"179.{div}.{mod}.1/24"
    elif device == "2":
        return f"179.{div}.{mod}.2/24"
    elif device == "bridge":
        return f"179.{div}.{mod}.0/24"
    else:
        raise ValueError(f"subnet_router_router_extern: unknown device {device}")

def subnet_router_IXP(n_grp: int, n_ixp: int, device: str):
    if device == "group":
        return f"180.{n_ixp}.0.{n_grp}/24"
    elif device == "IXP":
        return f"180.{n_ixp}.0.{n_ixp}/24"
    elif device == "bridge":
        return f"180.{n_ixp}.0.0/24"
    else:
        raise ValueError(f"subnet_router_IXP: unknown device {device}")

def subnet_router_MEASUREMENT(n_grp: int , device: str):
    if device == "group":
        return f"{n_grp}.0.199.1/24"
    elif device == "measurement":
        return f"{n_grp}.0.199.2/24"
    elif device == "bridge":
        return f"{n_grp}.0.199.0/24"
    else:
        raise ValueError(f"subnet_router_MEASUREMENT: unknown device {device}")

def subnet_router_MATRIX(n_grp: int, device: str):
    if device == "group":
        return f"{n_grp}.0.198.1/24"
    elif device == "matrix":
        return f"{n_grp}.0.198.2/24"
    elif device == "bridge":
        return f"{n_grp}.0.198.0/24"
    else:
        raise ValueError(f"subnet_router_MATRIX: unknown device {device}")

def subnet_router_DNS(n_grp: int, device: str):
    if device == "group":
        return f"198.{n_grp}.0.1/24"
    elif device == "measurement":
        return f"198.255.0.1/24"
    elif device == "dns-group":
        return f"198.{n_grp}.0.2/24"
    elif device == "dns":
        return f"198.0.0.100/24"
    elif device == "dns-measurement":
        return f"198.255.0.2/24"
    elif device == "bridge":
        return f"198.0.0.0/24"
    else:
        raise ValueError(f"subnet_router_DNS: unknown device {device}")

def subnet_ext_sshContainer(n_grp: int, device: str):
    if device == "sshContainer":
        return f"157.0.0.{n_grp + 10}/24"
    elif device == "MEASUREMENT":
        return f"157.0.0.250/24"
    elif device == "bridge":
        return f"157.0.0.1/24"
    elif device == "docker":
        return f"157.0.0.0/24"
    else:
        raise ValueError(f"subnet_ext_sshContainer: unknown device {device}")

def subnet_sshContainer_groupContainer(n_grp: int, n_router: int, n_layer2: int, device: str):
    if device == "sshContainer":
        return f"158.{n_grp}.0.2/16"
    elif device == "MEASUREMENT":
        return f"158.{n_grp}.0.3/16"
    elif device == "router":
        return f"158.{n_grp}.{n_router + 10}.1/16"
    elif device == "L3-host":
        return f"158.{n_grp}.{n_router + 10}.2/16"
    elif device == "switch":
        return f"158.{n_grp}.100.{n_layer2 + 3}/16"
    elif device == "L2-host":
        return f"158.{n_grp}.200.{n_layer2 + 3}/16"
    elif device == "bridge":
        return f"158.{n_grp}.0.1/16"
    elif device == "docker":
        return f"158.{n_grp}.0.0/16"
    else:
        raise ValueError(f"subnet_sshContainer_groupContainer: unknown device {device}")
