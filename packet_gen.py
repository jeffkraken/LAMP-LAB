# generate packets for review with noise
from scapy.all import *
import random

# FTP login credentials
username = "sqladmin"
password = "p!nkMouse23"

# Base Ethernet & IP
eth = Ether()
ip = IP(src="192.168.1.100", dst="192.168.1.10")
tcp = TCP(sport=12345, dport=21, flags="PA", seq=1000, ack=2000)

# --- Generate "noise" packets ---
def random_icmp():
    return Ether()/IP(src=f"192.168.1.{random.randint(2,254)}",
                      dst=f"192.168.1.{random.randint(2,254)}")/ICMP()

def random_arp():
    return Ether(dst="ff:ff:ff:ff:ff:ff")/ARP(
        op=1,  # who-has
        psrc=f"192.168.1.{random.randint(2,254)}",
        pdst=f"192.168.1.{random.randint(2,254)}"
    )

def random_dns():
    qname = random.choice(["example.com", "test.local", "randomsite.org"])
    return Ether()/IP(src=f"192.168.1.{random.randint(2,254)}",
                      dst="8.8.8.8")/UDP(sport=random.randint(1024,65535), dport=53)/DNS(rd=1,qd=DNSQR(qname=qname))

def generate_noise(count=5):
    noise = []
    for _ in range(count):
        pkt_type = random.choice([random_icmp, random_arp, random_dns])
        noise.append(pkt_type())
    return noise

# --- FTP Packets ---
pkt1 = eth / ip / tcp / Raw(load=f"USER {username}\r\n")
tcp.seq += len(pkt1[Raw].load)
pkt2 = eth / ip / tcp / Raw(load=f"PASS {password}\r\n")

# Mix noise and FTP packets
packets = []
packets.extend(generate_noise(5))
packets.append(pkt1)
packets.extend(generate_noise(3))
packets.append(pkt2)
packets.extend(generate_noise(5))

# Save packets to PCAP
wrpcap("netaudit.pcap", packets)

print("PCAP file created: netaudit.pcap")
