#!/usr/bin/env python3
"""Collect UDP payloads into a length-prefixed binary file for offline checking.

By default passive: sends NO packets. --trigger-host explicitly enables one
START message; use only with a trusted, known device.
"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import socket
import struct
import sys

def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--listen',default='0.0.0.0',help='local interface bind address')
    p.add_argument('--port',type=int,default=4991)
    p.add_argument('--count',type=int,required=True)
    p.add_argument('--timeout',type=float,default=10.0,help='per-packet timeout')
    p.add_argument('--src-ip',help='allow only UDP source IP')
    p.add_argument('--output',required=True)
    p.add_argument('--metadata',help='optional JSON Lines sidecar with sender/receive-time')
    p.add_argument('--trigger-host',help='optional trigger destination IP/host')
    p.add_argument('--trigger-text',default='START',help='trigger payload, only used with --trigger-host')
    a=p.parse_args(argv)
    if not (1<=a.port<=65535) or a.count<1 or a.timeout<=0:
        p.error('port/count/timeout out of range')
    if a.metadata and Path(a.output).resolve()==Path(a.metadata).resolve():
        p.error('--metadata and --output must differ')
    output=Path(a.output)
    if output.exists() or (a.metadata and Path(a.metadata).exists()):
        p.error('output/metadata path already exists; choose a new filename to preserve evidence')
    output.parent.mkdir(parents=True,exist_ok=True)
    meta_file=None
    accepted=0
    try:
        sock=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
        with sock:
            sock.bind((a.listen,a.port))
            sock.settimeout(a.timeout)
            if a.metadata:
                mp=Path(a.metadata)
                mp.parent.mkdir(parents=True,exist_ok=True)
                meta_file=mp.open('w',encoding='utf-8')
            try:
                with output.open('wb') as f:
                    if a.trigger_host:
                        sock.sendto(a.trigger_text.encode('utf-8'),(a.trigger_host,a.port))
                        print(f'[INFO] sent requested trigger to {a.trigger_host}:{a.port}')
                    while accepted<a.count:
                        payload,(ip,src_port)=sock.recvfrom(65535)
                        if a.src_ip and ip!=a.src_ip:
                            continue
                        f.write(struct.pack('!I',len(payload)))
                        f.write(payload)
                        accepted+=1
                        if meta_file:
                            meta_file.write(json.dumps({'ordinal':accepted,'src_ip':ip,'src_port':src_port,
                                'received_utc':datetime.now(timezone.utc).isoformat(),
                                'payload_length':len(payload)})+'\n')
            finally:
                if meta_file:
                    meta_file.close()
    except (OSError,socket.timeout) as exc:
        print(f'[FAIL] capture incomplete: {accepted}/{a.count}; {exc}',file=sys.stderr)
        return 1
    print(f'[PASS] captured {accepted}/{a.count} UDP application payloads to {a.output}')
    print('[NOTE] No wire-level loss/completeness or FPGA transmit throughput is proven by this output.')
    return 0

if __name__=='__main__':
    sys.exit(main())
