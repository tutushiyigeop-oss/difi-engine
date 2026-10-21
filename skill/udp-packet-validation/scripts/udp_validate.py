#!/usr/bin/env python3
"""Generic UDP payload validator. Standard library only; no DIFI assumptions.

Exit: 0 pass, 1 validation failure, 2 invalid invocation/IO/format.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import sys
from udp_pcap import PacketFormatError, UdpPacket, read_udp_pcap, read_length_prefixed

class ProfileError(ValueError):
    pass

def positive_integer(value, key, allow_zero=False):
    if type(value) is not int or value < (0 if allow_zero else 1):
        raise ProfileError(f'{key} must be {"nonnegative" if allow_zero else "positive"} integer')
    return value

def normalize_profile(data: dict) -> dict:
    if not isinstance(data, dict):
        raise ProfileError('profile must be JSON object')
    filt = data.get('filter', {})
    if not isinstance(filt, dict):
        raise ProfileError('filter must be JSON object')
    for key in filt:
        if key not in ('src_ip','dst_ip','src_port','dst_port'):
            raise ProfileError(f'unknown filter field: {key}')
    for key in ('src_port','dst_port'):
        if key in filt:
            val = positive_integer(filt[key], key)
            if val > 65535:
                raise ProfileError(f'{key} out of range')
    for key in ('src_ip','dst_ip'):
        if key in filt and not isinstance(filt[key], str):
            raise ProfileError(f'{key} must be string')
    count = positive_integer(data.get('expected_count'), 'expected_count')
    minlen = positive_integer(data.get('min_payload_length', 0), 'min_payload_length', allow_zero=True)
    maxlen = positive_integer(data.get('max_payload_length', 65507), 'max_payload_length', allow_zero=True)
    if maxlen > 65507 or maxlen < minlen:
        raise ProfileError('invalid min/max_payload_length')
    golden = data.get('golden_payloads_hex')
    if golden is not None:
        if not isinstance(golden,list) or len(golden) != count:
            raise ProfileError('golden_payloads_hex must have expected_count entries')
        try:
            golden = [bytes.fromhex(x) for x in golden]
        except (ValueError, TypeError) as exc:
            raise ProfileError(f'invalid hex payload: {exc}') from exc
    seq = data.get('sequence')
    if seq is not None:
        if not isinstance(seq, dict):
            raise ProfileError('sequence must be object')
        offset = positive_integer(seq.get('offset',0),'sequence.offset',True)
        width = positive_integer(seq.get('width',1),'sequence.width')
        if width not in (1,2,4,8):
            raise ProfileError('sequence.width must be 1,2,4,8 bytes')
        mask = seq.get('mask', (1 << (width*8))-1)
        if type(mask) is not int or mask < 0 or mask >= (1 << (width*8)):
            raise ProfileError('sequence.mask out of range')
        shift = positive_integer(seq.get('shift',0),'sequence.shift',True)
        if shift >= width*8:
            raise ProfileError('sequence.shift out of range')
        mod = positive_integer(seq.get('modulus',256),'sequence.modulus')
        if seq.get('endian','big') not in ('big','little'):
            raise ProfileError('sequence.endian invalid')
        start = seq.get('start',0)
        if type(start) is not int or not (0 <= start < mod):
            raise ProfileError('sequence.start invalid')
        seq = dict(offset=offset,width=width,mask=mask,shift=shift,modulus=mod,
                   endian=seq.get('endian','big'),start=start)
    return dict(filter=filt,expected_count=count,min_payload_length=minlen,
                max_payload_length=maxlen,golden_payloads=golden,sequence=seq)

def check_packets(packets: list[UdpPacket], profile: dict, metadata_available: bool) -> dict:
    cfg = normalize_profile(profile)
    filters=cfg['filter']
    if filters and not metadata_available:
        raise ProfileError('source/destination filters require PCAP; capture-bin has no IP/port metadata')
    selected = []
    for packet in packets:
        if all(getattr(packet, k) == v for k,v in filters.items()):
            selected.append(packet)
    errors=[]
    if len(selected)!=cfg['expected_count']:
        errors.append(f'count mismatch: expected={cfg["expected_count"]}, got={len(selected)}')
    if not selected:
        errors.append('zero matching UDP packets')
    for i,p in enumerate(selected):
        if not cfg['min_payload_length'] <= len(p.payload) <= cfg['max_payload_length']:
            errors.append(f'packet[{i}] payload length={len(p.payload)} outside configured bounds')
        g=cfg['golden_payloads']
        if g is not None:
            if i >= len(g):
                errors.append(f'packet[{i}] unexpected extra payload')
            elif p.payload != g[i]:
                errors.append(f'packet[{i}] golden payload mismatch')
        seq=cfg['sequence']
        if seq is not None:
            start=seq['offset'];end=start+seq['width']
            if len(p.payload)<end:
                errors.append(f'packet[{i}] too short for sequence field')
            else:
                extracted=(int.from_bytes(p.payload[start:end],seq['endian']) & seq['mask']) >> seq['shift']
                expected=(seq['start'] + i) % seq['modulus']
                if extracted!=expected:
                    errors.append(f'packet[{i}] sequence mismatch expected={expected}, got={extracted}')
    return {'result':'PASS' if not errors else 'FAIL','selected_packets':len(selected),
            'payload_bytes':sum(len(p.payload) for p in selected), 'errors':errors,
            'note':'application/PCAP payload validation only; not a wire-rate or reliability benchmark'}

def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    g=parser.add_mutually_exclusive_group(required=True)
    g.add_argument('--pcap', help='classic Ethernet PCAP (not pcapng)')
    g.add_argument('--capture-bin', help='4-byte BE length-prefixed UDP payloads')
    parser.add_argument('--profile',required=True,help='JSON profile')
    parser.add_argument('--report',help='optional JSON report path')
    args=parser.parse_args(argv)
    try:
        profile=json.loads(Path(args.profile).read_text(encoding='utf-8'))
        packets=list(read_udp_pcap(args.pcap) if args.pcap else read_length_prefixed(args.capture_bin))
        result=check_packets(packets,profile,metadata_available=bool(args.pcap))
    except (OSError, ValueError, PacketFormatError) as exc:
        print(f'[ERROR] {exc}',file=sys.stderr)
        return 2
    if args.report:
        try:
            Path(args.report).parent.mkdir(parents=True,exist_ok=True)
            Path(args.report).write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
        except OSError as exc:
            print(f'[ERROR] report: {exc}',file=sys.stderr)
            return 2
    print(f'[{result["result"]}] packets={result["selected_packets"]}, bytes={result["payload_bytes"]}')
    for msg in result['errors']:
        print(f'[FAIL] {msg}')
    return 0 if result['result']=='PASS' else 1

if __name__=='__main__':
    sys.exit(main())
