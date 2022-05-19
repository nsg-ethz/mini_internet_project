# These are generic test functions

import ipaddress
import json
import random
import sqlite3
import time

from scapy.all import *

def random_ip(cidr):
    network = ipaddress.ip_network(cidr)
    netmask = int(network.netmask)
    hostmask = int(network.hostmask)
    network_address = int(network.network_address)

    # exclude all zeroes and all ones
    randomip = random.randint(1, 2**32 - 2)

    randomip = randomip & hostmask
    randomip = network_address | randomip

    return ipaddress.IPv4Address(randomip).exploded

class ASTest():
    def __init__(self, c, nr, name):
        self.c = c
        self.nr = nr
        self.name = name
        t = int(time.time()).to_bytes(5, 'big')
        self.test_id = (nr.to_bytes(4, 'big') + t + randstring(7)).hex()

        self.c.execute("""INSERT INTO test_runs(runid, ts)
                     VALUES(?, julianday())""", (self.test_id,))

    def log_received(self, pkts):
        for pkt in pkts:
            details = {}
            load = pkt.load.decode('ascii')
            details['payload'] = load
            load = load.split(',')

            if len(load) < 7:
                p_type = 'O'
            else:
                if load[0] != self.test_id:
                    p_type = 'O'
                else:
                    p_type = load[1]
                    if p_type == 'P':
                        icmp = pkt.getlayer(ICMP)
                        if icmptypes[icmp.type] not in ('echo-reply', 'echo-request'):
                            # This is not expected
                            p_type = 'O'
                    elif p_type == 'U':
                        udp = pkt.getlayer(UDP)
                        if udp is None:
                            p_type = 'O'
                    elif p_type == 'T':
                        ip = pkt.getlayer(IP)
                        eip = pkt.getlayer(IPerror)
                        icmp = pkt.getlayer(ICMP)
                        if ip is None or eip is None or icmp is None:
                            p_type= 'O'
                        elif icmptypes[icmp.type] != 'time-exceeded':
                                p_type = 'O'
                        else:
                            details['IP'] = {'src': ip.src, 'dst': ip.dst}
                            details['IPerror'] = {'src': eip.src, 'dst': eip.dst}
                    else:
                        p_type = 'O'

            if p_type == 'O':
                details['raw'] = bytes(pkt).hex()
                details['pretty'] = pkt.show(dump=True)

            self.c.execute("""INSERT INTO packets(sr, type, ts_unix, loc, runid, details)
                         VALUES('R', ?, ?, ?, ?, ?)""",
                      (p_type, pkt.time, pkt.sniffed_on, load[0], json.dumps(details)))

    def log_send(self, pkts, p_type, iface):
        for pkt in pkts:
            details = {'payload': pkt.load.decode('ascii')}
            self.c.execute("""INSERT INTO packets(sr, type, ts_unix, loc, runid, details)
                         VALUES('S', ?, ?, ?, ?, ?)""",
                      (p_type, pkt.sent_time, iface, self.test_id, json.dumps(details)))

    def gen_details(self, p_type, src, src_ip, dst, dst_ip, cnt, ttl=None):
        if ttl:
            d = "{},{},{},{},{},{},{},{}".format(
                    self.test_id, p_type, src, src_ip, dst, dst_ip, cnt, ttl)
        else:
            d = "{},{},{},{},{},{},{}".format(
                    self.test_id, p_type, src, src_ip, dst, dst_ip, cnt)
        return d

    def test_send_udp(self, iface, src, src_ip, dst, dst_ip):
        pkts = []
        for i in range(3):
            if '/' in src_ip:
                f_ip = random_ip(src_ip)
            else:
                f_ip = src_ip

            if '/' in dst_ip:
                t_ip = random_ip(dst_ip)
            else:
                t_ip = dst_ip

            d = self.gen_details('U', src, f_ip, dst, t_ip, i)

            #TODO: Randomize ports
            pkts.append(IP(src=f_ip, dst=t_ip)/
                         UDP(sport=5000, dport=5000)/
                         Raw(d.encode('ascii')))

        p = send(pkts, count=1, return_packets=True, iface=iface)
        self.log_send(p, 'U', iface)

    def test_ping_host(self, iface, src, src_ip, dst, dst_ip):
        pkts = []
        for i in range(3):
            if '/' in src_ip:
                f_ip = random_ip(src_ip)
            else:
                f_ip = src_ip

            if '/' in dst_ip:
                t_ip = random_ip(dst_ip)
            else:
                t_ip = dst_ip

            d = self.gen_details('P', src, f_ip, dst, t_ip, i)
            pkts.append(IP(src=f_ip, dst=t_ip)/
                         ICMP()/
                         Raw(d.encode('ascii')))
        p = send(pkts, count=1, return_packets=True, iface=iface)
        self.log_send(p, 'P', iface)

    def test_do_traceroute(self, iface, src, src_ip, dst, dst_ip):
        pkts = []
        for i in range(3):
            if '/' in src_ip:
                f_ip = random_ip(src_ip)
            else:
                f_ip = src_ip

            if '/' in dst_ip:
                t_ip = random_ip(dst_ip)
            else:
                t_ip = dst_ip

            for ttl in range(1, 11):
                d = self.gen_details('T', src, f_ip, dst, t_ip, i, ttl)
                pkts.append(IP(src=f_ip, dst=t_ip, ttl=ttl)/
                            UDP(sport=5000, dport=5000)/
                            Raw(d.encode('ascii')))
        p = send(pkts, count=1, return_packets=True, iface=iface)
        self.log_send(p, 'T', iface)

    def reset(self, name=None):
        self.name = name
