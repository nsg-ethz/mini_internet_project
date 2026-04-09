from ipaddress import IPv4Network, IPv4Address
from dataclasses import dataclass

@dataclass
class LinkSubnet:
    network: IPv4Network
    endpoint_ips: tuple[IPv4Address,IPv4Address] | None

class SubnetScheme:
    """Mini-internet IP addressing scheme"""
    
    @staticmethod
    def get_as_as_subnet(as1: int, as2: int, custom_subnet: IPv4Network | None = None) -> LinkSubnet:
        # TODO: this is a work in progress
        #       i)  remove the possibility of definining a custom subnet altogether, we need to just compute a fixed one I think
        #       ii) maybe come up with a better scheme for the endpoint_ips possibly being None?
        if custom_subnet:
            return LinkSubnet(
                network=IPv4Network(custom_subnet),
                endpoint_ips=None
            )
        else:
            raise NotImplementedError("Cannot handle non-custom subnets for AS-to-AS links yet")
            
    @staticmethod
    def get_as_ixp_subnet(as_num: int, ixp_num: int) -> LinkSubnet:
        """ All ASes on same IXP share 180.`ixp_num`.0.0/24 """

        as_endpoint_ip = IPv4Address(f"180.{ixp_num}.0.{as_num}")
        ixp_endpoint_ip = IPv4Address(f"180.{ixp_num}.0.{ixp_num}")
        return LinkSubnet(
            network=IPv4Network(f"180.{ixp_num}.0.0/24"),
            endpoint_ips=(as_endpoint_ip,ixp_endpoint_ip)
        )