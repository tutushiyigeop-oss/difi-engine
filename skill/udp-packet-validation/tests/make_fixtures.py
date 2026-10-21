"""Generate synthetic PCAP fixtures; these are NOT from a real FPGA/Consortium."""
from pathlib import Path
import struct
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from udp_pcap import PcapFrame, write_length_prefixed, write_pcap
from difi_b5_validate import iq

HERE=Path(__file__).resolve().parent/'fixtures'

def make_b5_packets(rounds=20,samples=256):
    result=[]
    for i in range(rounds+2):
        typ=5 if i==0 else (4 if i==1 else 1)
        sid=2 if i==0 else 1
        seq=0 if i<2 else (i-2)&15
        count=11 if i==0 else (27 if i==1 else 7+samples)
        w=[0]*count
        w[0]=(typ<<28)|0x08600000|(seq<<16)|count|(0x01000000 if typ!=1 else 0)
        w[1]=sid
        w[2]=0x006A621E
        if typ==5:
            w[3]=0x00010004
            w[7]=0x80000002
        elif typ==4:
            w[3]=1
            w[7]=0xFBB98000
            w[25]=0xA00003CF
        else:
            for sample_index in range(samples):
                w[7+sample_index]=iq(i-2,sample_index)
        result.append(struct.pack('!'+str(len(w))+'I',*w))
    return result

def ipv4_checksum(data):
    if len(data)%2:data+=b'\0'
    s=sum(struct.unpack('!%dH'%(len(data)//2),data))
    while s>>16:s=(s&0xffff)+(s>>16)
    return (~s)&0xffff

def ether_udp(payload,src='192.168.1.10',dest='192.168.1.20',sport=4991,dport=4991, vlan=False):
    import ipaddress
    ipbody=struct.pack('!HHHH',sport,dport,8+len(payload),0)+payload
    header=struct.pack('!BBHHHBBH4s4s',0x45,0,20+len(ipbody),0x100,0,64,17,0,
        ipaddress.IPv4Address(src).packed,ipaddress.IPv4Address(dest).packed)
    header=header[:10]+struct.pack('!H',ipv4_checksum(header))+header[12:]
    eth=b'\x02\x00\x00\x00\x00\x02'+b'\x02\x00\x00\x00\x00\x01'
    eth+=(b'\x81\x00\x00\x01\x08\x00' if vlan else b'\x08\x00')
    return eth+header+ipbody

def frames_for_packets(packets, vlan=False):
    return [PcapFrame(100+i,1000,ether_udp(x,vlan=vlan),14+20+8+len(x)+(4 if vlan else 0))
            for i,x in enumerate(packets)]

def create_all(path=HERE):
    path=Path(path)
    path.mkdir(parents=True,exist_ok=True)
    packets=make_b5_packets()
    write_pcap(path/'b5_synthetic_valid.pcap',frames_for_packets(packets))
    write_length_prefixed(path/'b5_synthetic_valid.bin',packets)
    bad=list(packets)
    payload=bytearray(bad[-1]);payload[-1]^=1;bad[-1]=bytes(payload)
    write_pcap(path/'b5_synthetic_bad_iq.pcap',frames_for_packets(bad))
    write_length_prefixed(path/'b5_synthetic_bad_iq.bin',bad)
    write_pcap(path/'b5_synthetic_vlan.pcap',frames_for_packets(packets,vlan=True))
    write_pcap(path/'b5_synthetic_missing.pcap',frames_for_packets(packets[:-1]))
    # Tiny generic profile/fixture with a one-byte sequence field.
    generic=[bytes([j])+b'PAYLOAD' for j in range(3)]
    write_pcap(path/'generic_valid.pcap',frames_for_packets(generic))
    write_length_prefixed(path/'generic_valid.bin',generic)
    generic_bad=list(generic);generic_bad[1]=bytes([8])+b'PAYLOAD'
    write_pcap(path/'generic_bad_seq.pcap',frames_for_packets(generic_bad))

if __name__=='__main__':
    create_all()
    print('[PASS] synthetic fixtures generated, not hardware capture')
