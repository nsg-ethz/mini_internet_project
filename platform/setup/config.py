from dataclasses import dataclass, field
from collections import defaultdict
from enum import Enum
from ipaddress import IPv4Network
from subnets import LinkSubnet, SubnetScheme
import argparse


def read_config(args: argparse.Namespace, filename: str) -> list[list[str]]:
    """
    Helper function to pull text configs from a whitespace-separated file
    """
    config_file = args.config / filename
    if not config_file.exists():
        raise FileNotFoundError(f"Configuration file not found: {config_file}")
    with config_file.open() as f:
        return [line.split() for line in f if line.strip()]

@dataclass
class LinkData:
    throughput_mbit: int
    delay_ms: float
    max_buffer_ms: int

    @classmethod
    def from_triple(cls, config: list[str]) -> "LinkData":
        assert len(config) == 3, "The config of a link must be a triple"
        
        throughput = config[0]
        if throughput.endswith("mbit"):
            throughput = throughput[:-4]
        else:
            raise ValueError(f"Throughput must be in mbit, got: {config[0]}")
        
        delay = config[1]
        if delay.endswith("ms"):
            delay = delay[:-2]
        else:
            raise ValueError(f"Delay must be in ms, got: {config[1]}")
        
        max_buffer = config[2]
        if max_buffer.endswith("ms"):
            max_buffer = max_buffer[:-2]
        else:
            raise ValueError(f"Delay must be in ms, got: {config[2]}")
        
        return cls(
            throughput_mbit = int(throughput),
            delay_ms = float(delay),
            max_buffer_ms = int(max_buffer)
        )

class Relationship(Enum):
    PROV_CUST = "Provider/Customer"
    PEER = "Peer/Peer"

    @classmethod
    def from_roles(cls, role_a: str, role_b: str) -> "Relationship":
        pair = (role_a.strip().lower(), role_b.strip().lower())

        if pair == ("provider", "customer"):
            return cls.PROV_CUST
        elif pair == ("peer", "peer"):
            return cls.PEER
        else:
            raise ValueError(f"Invalid relationship: {role_a}/{role_b}")

@dataclass
class ExternalLink:
    """ A directed link between devices in different ASes """
    src: tuple[int, str]
    dst: tuple[int, str]
    relationship: Relationship
    data: LinkData
    subnet: LinkSubnet
    community_values: list[int]

    @classmethod
    def from_config(cls, link_config: list[str], subnet: LinkSubnet, community_values: list[int] = []) -> "ExternalLink":
        src = (int(link_config[0]), link_config[1])
        dst = (int(link_config[3]), link_config[4])
        # Get the type of link
        relationship = Relationship.from_roles(link_config[2], link_config[5])
        link_data = LinkData.from_triple(link_config[6:9])
        return cls(src, dst, relationship, link_data, subnet, community_values)

@dataclass
class InternalLink:
    """ A link between internal devices in an AS """
    endpoints: tuple[str,str]
    data: LinkData

    @classmethod
    def from_partial_config(cls, src: str, dst: str, link_config: list[str]) -> "InternalLink":
        sorted_endpoints = sorted([src, dst])
        endpoints: tuple[str, str] = (sorted_endpoints[0], sorted_endpoints[1])
        return cls(endpoints, LinkData.from_triple(link_config))

class HostType(Enum):
    HOST = "host"
    ROUTINATOR = "routinator"
    KRILL = "krill"

@dataclass(frozen=True) # This needs to be hashable
class Host:
    container_name: str
    type: HostType
    l2_id: int | None
    vlan: int | None

    @classmethod
    def from_str(cls, value: str, l2_id: int | None, vlan: int| None) -> "Host | None":
        """Parse a string to a Host along with its type"""

        if value == "N/A":
            return None
        # This happens if the host is an L2 host
        if ":" not in value:
            # Plain container path is always a HOST
            return cls(value, HostType.HOST, l2_id, vlan)

        information, container = value.split(":", maxsplit=1)
        # The additional information can describe a lot of things
        try:
            # If we can parse it, great
            host_type = HostType(information)
        except ValueError:
            # Anything else still has a host
            # WARN: We purposefully ignore the information about the L2 stuff here
            host_type = HostType.HOST

        return cls(container, host_type, l2_id, vlan)

@dataclass
class Switch:
    name: str
    mac: str  # Maybe we want a better data structure for this?
    bridge_id: int

    @classmethod
    def from_config(cls, config: list[str]) -> "Switch":
        return cls(
            name=config[1],
            mac=config[3],
            bridge_id=int(config[4])
        )

@dataclass
class L2Network:
    name: str
    switches: list[Switch] = field(default_factory=list[Switch])
    hosts: dict[str, Host] = field(default_factory=dict[str, Host])
    links: list[InternalLink] = field(default_factory=list[InternalLink])

def l2_networks_from_configs(args: argparse.Namespace, routers: set[str], switches_config: str, hosts_config: str, links_config: str) -> dict[str, L2Network]:
    """
    Constructs L2 network topology from configuration files.
    Parses configuration files for switches, hosts, and links to build a dictionary
    of L2Network objects representing the layer 2 network topology.
    """

    l2_networks: dict[str, L2Network] = {}

    # First populate all the switches
    for switch_config in read_config(args, switches_config):
        if switch_config[2] != "N/A":
            assert switch_config[2] in routers, f"The router ({switch_config[2]}) this switch ({switch_config[1]}) is trying to connect to does not exist"
        switch = Switch.from_config(switch_config)
        net_name = switch_config[0]
        
        if net_name not in l2_networks:
            l2_networks[net_name] = L2Network(name=net_name)

        l2_networks[net_name].switches.append(switch)

    # Then the hosts and their respective links
    for id, host_config in enumerate(read_config(args, hosts_config)):
        net_name = host_config[2]
        assert net_name in l2_networks.keys(), f"The L2 network ({net_name}) this host ({host_config[0]}) is a part of does not exist"

        host_name = host_config[0]
        vlan = int(host_config[7])
        host = Host.from_str(host_config[1], id, vlan)
        assert host is not None, "Unparsable host in L2 network"
        l2_networks[net_name].hosts[host_name] = host

        # Now the host links
        host_switch = host_config[3]
        assert host_switch in [switch.name for switch in  l2_networks[net_name].switches], f"This host ({host_config[0]}) is trying to connect to a switch that does not exist ({host_config[3]})"
        l2_networks[net_name].links.append(InternalLink.from_partial_config(host_name, host_switch, host_config[4:7]))

    # Finally the links
    for link_config in read_config(args, links_config):
        net_name = link_config[0]
        assert net_name == link_config[2], "It is not possible to connect two switches that are in different L2 networks"

        src = link_config[1]
        dst = link_config[3]
        l2_networks[net_name].links.append(InternalLink.from_partial_config(src, dst, link_config[4:7]))

    return l2_networks


class Service(Enum):
    DNS = "DNS"
    MATRIX = "MATRIX"
    MATRIX_TARGET = "MATRIX_TARGET"
    MEASUREMENT = "MEASUREMENT"

    @classmethod
    def from_str(cls, value: str) -> "Service | None":
        """Parse a string to a Service enum, returning None for 'N/A'"""
        if value == "N/A":
            return None
        try:
            return cls(value)
        except ValueError:
            raise ValueError(f"Invalid service value: {value}")

class Access(Enum):
    VTYSH = "vtysh"
    LINUX = "linux"
    NONE = "none"

    @classmethod
    def from_str(cls, value: str) -> "Access":
        """Parse a string to an Access enum, can only be linux or vtysh"""
        try:
            return cls(value)
        except ValueError:
            raise ValueError(f"Invalid service value: {value}")


@dataclass
class Router:
    name: str
    services: set[Service] = field(default_factory=set[Service])
    hosts: set[Host] = field(default_factory=set[Host])
    access: Access = Access.NONE

    @classmethod
    def from_configs(cls, config: list[list[str]]) -> "Router":
        """
        Builds a router from an L3 router configuration line
        """
        # Sanity checks, ensure that all config lines share the same name and access                
        name = config[0][0]
        access_str = config[0][3]
        for row in config:
            if row[0] != name:
                raise ValueError(f"Multiline configs must share the same router name. Expected '{name}', got '{row[0]}'")
            if row[3] != access_str:
                raise ValueError(f"Multiline configs must share the same type of access. Expected '{access_str}', got '{row[3]}'")
        
        access = Access.from_str(access_str)
        # Extract all services
        services: set[Service] = {s for row in config if (s := Service.from_str(row[1])) is not None}
        # Extract all hosts
        hosts: set[Host] = {h for row in config if (h := Host.from_str(row[2], None, None)) is not None}
        return cls(name, services, hosts, access)

def routers_from_config(args: argparse.Namespace, routers_config: str) -> dict[str, Router]:
    """
    Builds a map of routers, indexed by their names, based on an L3 router configuration file
    """
    router_configs = read_config(args, routers_config)
    # Group them by router, as a router may have multiple lines
    grouped: dict[str, list[list[str]]] = defaultdict(list)

    for row in router_configs:
        router_name = row[0]
        grouped[router_name].append(row)

    if args.verbose:
        print(f"Found {len(grouped)} routers in configuration '{routers_config}'")

    # Then merge
    return { router_name: Router.from_configs(configs) for router_name, configs in grouped.items() }

@dataclass
class IXP:
    routers: dict[str, Router]
    
    @classmethod
    def from_config(cls, config: list[str]) -> "IXP":
        assert config[2] == "Config", f"IXP {config[0]} can only be autoconfigured"
        assert all([c == "N/A" for c in config[3:]]), f"Cannot set links or routers on IXP {config[0]}"

        # TODO: make this smarter, ideally change the config files to read an actual router name for the IXP one
        return cls({"None": Router("None")})
        

@dataclass
class AS:
    auto: bool
    routers: dict[str, Router]
    internal_links: list[InternalLink]
    l2_networks: dict[str, L2Network]

    @classmethod
    def from_config(cls, args: argparse.Namespace, config: list[str]) -> "AS":
        """
        Builds an overview of an AS based on the provided configuration 
        """
        if args.verbose:
            print(f"Building AS {config[0]}")
        # Save these to make sure they are available for L2 construction
        routers = routers_from_config(args, config[3])
        # Build the internal links
        links: list[InternalLink] = []
        for link_config in read_config(args, config[4]):
            src = link_config[0]
            dst = link_config[1]
            assert (src in routers and dst in routers), "Trying to connect two routers that do not exist"
            links.append(InternalLink.from_partial_config(src, dst, link_config[2:]))

        return cls(
            auto = config[2] == "Config",
            routers = routers,
            internal_links = links,
            l2_networks = l2_networks_from_configs(args, set(routers.keys()), config[5], config[6], config[7])
        )

type Domain = IXP|AS

def domain_from_config(args: argparse.Namespace, config: list[str]) -> Domain:

    type = config[1]
    if type == "AS":
        return AS.from_config(args, config)
    elif type == "IXP":
        return IXP.from_config(config)
    else:
        raise(ValueError)

@dataclass
class Topology:
    """
    The Topology class contains an overview of all ASes and their devices in the mini internet
    """
    
    as_es: dict[int, Domain]
    external_links: list[ExternalLink]

    @classmethod
    def from_config(cls, args :argparse.Namespace) -> "Topology":
        """
        Builds a view of the ASes in our network from a config file in which every row corresponds to a new AS
        """
        as_configs = read_config(args, "AS_config.txt")
        as_es = {int(config[0]): domain_from_config(args, config) for config in as_configs}
        # Configure the external links
        external_links: list[ExternalLink] = []
        for link_config in read_config(args, "aslevel_links.txt"):
            # Verify that the endpoints exist
            src_id = int(link_config[0])
            src_domain = as_es[int(src_id)]
            assert isinstance(src_domain, AS), f"Source AS {src_id} must be an AS, not an IXP"
            assert link_config[1] in src_domain.routers.keys(), f"Source router {link_config[1]} does not exist in AS {src_id}"
            dst_id = int(link_config[3])
            dst_domain = as_es[int(dst_id)]
            # Destinations can be either ASes or IXPs, IXPs have a single router in them
            assert link_config[4] in dst_domain.routers.keys(), f"Destination router {link_config[4]} does not exist in AS {dst_id}"
            
            # Dispatch based on endpoint types
            if isinstance(dst_domain, IXP):
                # AS to IXP link
                subnet = SubnetScheme.get_as_ixp_subnet(as_num=src_id, ixp_num=dst_id)

                # Get the community lists
                # TODO: can we think of a better way of doing this?
                raw_value = link_config[9]
                # Check if it's an IP address (should not happen in this branch)
                if '.' in raw_value or '/' in raw_value:
                    raise ValueError(f"Unexpected IP address format in AS-IXP link: {raw_value}")
                # Parse as comma-separated community values
                communities: list[int] = [int(x.strip()) for x in raw_value.split(',') if x.strip()]

                external_links.append(ExternalLink.from_config(link_config, subnet, communities))
            else:
                # AS to AS link
                # TODO: this will fail if AS to AS is not specified, eventually we may want to retire this field in the config altogether
                custom = IPv4Network(link_config[9], strict=True)
                subnet = SubnetScheme.get_as_as_subnet(src_id, dst_id, custom)

                external_links.append(ExternalLink.from_config(link_config, subnet))

        return cls(as_es, external_links)