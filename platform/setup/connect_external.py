from .config import *
from config.subnet_config import *
from .helper import *



def connect_external_router(config: Topology, directory: Path):

    for link in config.external_links:

        if isinstance(config.as_es[link.src[0]],IXP):
            cnt_1 = f"{link.src[0]}_IXP"
            intf_2 = f"ixp_{link.src[0]}"
            cnt_2 = f"{link.dst[0]}_{link.dst[1]}router"
            intf_1 =  f"grp_{link.dst[0]}"

        elif isinstance(config.as_es[link.dst[0]],IXP):
            cnt_1 = f"{link.src[0]}_{link.src[1]}router"
            intf_2 = f"grp_{link.src[0]}"
            cnt_2 = f"{link.dst[0]}_IXP"
            intf_1 =  f"ixp_{link.dst[0]}"
   
        else:
            cnt_1 = f"{link.src[0]}_{link.src[1]}router"
            intf_2 = f"ext_{link.src[0]}_{link.src[1]}"
            cnt_2 = f"{link.dst[0]}_{link.dst[1]}router"
            intf_1 =  f"ext_{link.dst[0]}_{link.dst[1]}"

        
        thrp = f"{link.data.throughput_mbit}mbit"
        delay = f"{link.data.delay_ms}ms"
        buffer = f"{link.data.max_buffer_ms}ms"

        connect_two_interfaces(cnt_1,intf_1,cnt_2,intf_2,(thrp,delay,buffer))


