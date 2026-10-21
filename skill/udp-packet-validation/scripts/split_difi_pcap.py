#!/usr/bin/env python3
"""Split classic Ethernet PCAP into DIFI B5 Version SID and Data/Context SID.

Keeps original Ethernet frames. Does not certify DIFI or rewrite UDP payload.
"""
import argparse
from pathlib import Path
import sys
from udp_pcap import PacketFormatError, extract_udp, read_pcap, write_pcap

def split_frames(frames, board_ip, dest_ip, port, version_sid, data_sid):
    version=[]
    context_data=[]
    unknown=[]
    matched=0
    for no,frame in enumerate(frames,1):
        packet=extract_udp(frame,no)
        if packet is None or packet.src_ip!=board_ip or packet.dst_ip!=dest_ip or packet.dst_port!=port:
            continue
        matched+=1
        b=packet.payload
        if len(b)<8 or len(b)%4:
            unknown.append(f'packet {no}: too short/misaligned DIFI payload')
            continue
        t=b[0]>>4
        sid=int.from_bytes(b[4:8],'big')
        if t==5 and sid==version_sid:
            version.append(frame)
        elif t in (1,4) and sid==data_sid:
            context_data.append(frame)
        else:
            unknown.append(f'packet {no}: unsupported type={t} sid={sid}')
    if not matched:
        raise PacketFormatError('no packets matched board IP, destination IP and UDP port')
    if unknown:
        raise PacketFormatError('unclassified packets: '+'; '.join(unknown))
    if not version or not context_data:
        raise PacketFormatError(f'need nonempty Version and Context/Data, found {len(version)} and {len(context_data)}')
    return version,context_data

def main(argv=None):
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--pcap',required=True)
    ap.add_argument('--board-ip',required=True)
    ap.add_argument('--pc-ip',required=True)
    ap.add_argument('--port',type=int,default=4991)
    ap.add_argument('--version-sid',type=int,default=2)
    ap.add_argument('--data-sid',type=int,default=1)
    ap.add_argument('--outdir',required=True)
    a=ap.parse_args(argv)
    try:
        version,context_data=split_frames(list(read_pcap(a.pcap)),a.board_ip,a.pc_ip,
                                          a.port,a.version_sid,a.data_sid)
        out=Path(a.outdir).resolve()
        if Path(a.pcap).resolve() in (out/'version_flow.pcap',out/'data_context_flow.pcap'):
            raise PacketFormatError('would overwrite source PCAP')
        if (out/'version_flow.pcap').exists() or (out/'data_context_flow.pcap').exists():
            raise PacketFormatError('destination already exists; use a fresh output directory')
        out.mkdir(parents=True,exist_ok=True)
        write_pcap(out/'version_flow.pcap', version)
        write_pcap(out/'data_context_flow.pcap',context_data)
    except (PacketFormatError,OSError,ValueError) as exc:
        print(f'[ERROR] {exc}',file=sys.stderr)
        return 2
    print(f'[PASS] split Version={len(version)} Context+Data={len(context_data)}; independent tool still required')
    return 0

if __name__=='__main__':
    sys.exit(main())
