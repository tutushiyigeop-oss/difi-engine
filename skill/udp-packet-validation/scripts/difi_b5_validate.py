#!/usr/bin/env python3
"""Strict DIFI B5 regression checker for the *specific documented test vector*.

Not a generic DIFI 1.1 compliance checker and not Consortium certification.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import sys
from udp_pcap import PacketFormatError, read_udp_pcap, read_length_prefixed, UdpPacket

class B5Error(ValueError):
    pass

def iq(round_idx: int, idx: int) -> int:
    special=(0x0001FFFF,0x7FFF8000,0xFFFE0003,0x00000000)
    if idx<4:
        return special[idx]
    iv=(0x1000+idx+0x200*round_idx)&0xFFFF
    qv=(0xA000+3*idx+0x11*round_idx)&0xFFFF
    return (iv << 16) | qv

def inspect(packets: list[UdpPacket], rounds: int = 20, samples: int = 256,
            data_sid: int = 1, version_sid: int = 2) -> dict:
    if not 4 <= samples <= 256:
        raise B5Error('B5 reference generator requires 4..256 IQ samples')
    if rounds<1:
        raise B5Error('rounds must be positive')
    errors=[]
    if len(packets) != rounds+2:
        errors.append(f'packet count expected={rounds+2}, got={len(packets)}')
    payload_count=0
    sample_count=0
    for pos,p in enumerate(packets):
        expected_type=5 if pos==0 else (4 if pos==1 else 1)
        expected_sid=version_sid if expected_type==5 else data_sid
        seq=0 if pos<=1 else (pos-2)&15
        expected_len=11 if pos==0 else (27 if pos==1 else 7+samples)
        payload_count+=len(p.payload)
        if len(p.payload) % 4:
            errors.append(f'packet[{pos}] non-word-aligned length {len(p.payload)}')
            continue
        words=[int.from_bytes(p.payload[i:i+4],'big') for i in range(0,len(p.payload),4)]
        if len(words)!=expected_len:
            errors.append(f'packet[{pos}] length expected={expected_len} words got={len(words)}')
            continue
        head=((expected_type<<28)|0x08600000|(seq<<16)|expected_len |
              (0x01000000 if expected_type in (4,5) else 0))
        if words[0]!=head:
            errors.append(f'packet[{pos}] word0 expected=0x{head:08X} got=0x{words[0]:08X}')
        if words[1]!=expected_sid:
            errors.append(f'packet[{pos}] Stream ID expected={expected_sid} got={words[1]}')
        if words[2]!=0x006A621E:
            errors.append(f'packet[{pos}] OUI mismatch')
        if expected_type==5:
            if words[3]!=0x00010004 or words[7]!=0x80000002:
                errors.append('version metadata mismatch')
        elif expected_type==4:
            if words[3]!=0x00000001 or words[7]!=0xFBB98000 or words[25]!=0xA00003CF:
                errors.append('context metadata mismatch')
        else:
            if words[3]!=0:
                errors.append(f'data packet[{pos}] class ID mismatch')
            r=pos-2
            for j in range(samples):
                if words[7+j]!=iq(r,j):
                    errors.append(f'data packet[{pos}] IQ[{j}] mismatch expected=0x{iq(r,j):08X} got=0x{words[7+j]:08X}')
                    break
            else:
                sample_count+=samples
    return dict(result='PASS' if not errors else 'FAIL', packets=len(packets),
                payload_bytes=payload_count, validated_iq_samples=sample_count,
                errors=errors, note='B5 fixed-vector self-check, NOT official DIFI protocol certification')

def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__)
    g=p.add_mutually_exclusive_group(required=True)
    g.add_argument('--pcap',help='classic Ethernet PCAP')
    g.add_argument('--capture-bin',help='4-byte big-endian length-prefixed UDP payloads')
    p.add_argument('--src-ip',default=None,help='filter source IP for PCAP; e.g. board 192.168.1.10')
    p.add_argument('--dst-ip',default=None,help='filter destination IP for PCAP')
    p.add_argument('--dst-port',type=int,default=None,help='filter destination UDP port for PCAP')
    p.add_argument('--rounds',type=int,default=20)
    p.add_argument('--samples',type=int,default=256)
    p.add_argument('--data-sid',type=int,default=1)
    p.add_argument('--version-sid',type=int,default=2)
    p.add_argument('--report')
    a=p.parse_args(argv)
    if a.capture_bin and any(x is not None for x in (a.src_ip,a.dst_ip,a.dst_port)):
        p.error('IP/port filters require PCAP; length-prefixed file has no network metadata')
    try:
        packets=list(read_udp_pcap(a.pcap) if a.pcap else read_length_prefixed(a.capture_bin))
        selected=[x for x in packets if (a.src_ip is None or x.src_ip==a.src_ip) and
                   (a.dst_ip is None or x.dst_ip==a.dst_ip) and
                   (a.dst_port is None or x.dst_port==a.dst_port)]
        result=inspect(selected,rounds=a.rounds,samples=a.samples,data_sid=a.data_sid,version_sid=a.version_sid)
        if not selected:
            result['result']='FAIL'
            result['errors'].append('zero matching packets')
        if a.report:
            Path(a.report).parent.mkdir(parents=True,exist_ok=True)
            Path(a.report).write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    except (OSError, ValueError) as exc:
        print(f'[ERROR] {exc}',file=sys.stderr)
        return 2
    print(f'[{result["result"]}] packets={result["packets"]} IQ={result["validated_iq_samples"]} bytes={result["payload_bytes"]}')
    for e in result['errors']:
        print(f'[FAIL] {e}')
    return 0 if result['result']=='PASS' else 1

if __name__=='__main__':
    sys.exit(main())
