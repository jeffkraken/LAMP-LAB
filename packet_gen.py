# generate packets for review
from scapy.all import *

# FTP login credentials
username = "sqladmin"
password = "p!nkMouse23"

# Create base packet layers
eth = Ether()
ip = IP(src="192.168.1.100", dst="192.168.1.10")
tcp = TCP(sport=12345, dport=21, flags="PA", seq=1000, ack=2000)

# FTP packets (user and password sent in plain text)
pkt1 = eth / ip / tcp / Raw(load="USER sqladmin\r\n")
tcp.seq += len(pkt1[Raw].load)
pkt2 = eth / ip / tcp / Raw(load="PASS p!nkMouse23\r\n")

# Save packets to a .pcap file
wrpcap("netaudit.pcap", [pkt1, pkt2])

print("PCAP file created: netaudit.pcap")
