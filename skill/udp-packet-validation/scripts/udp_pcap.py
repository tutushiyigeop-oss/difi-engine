#!/usr/bin/env python3
"""Dependency-free classic PCAP/Ethernet/IPv4/UDP and length-prefixed binary I/O.

No pcapng, IPv6, IP reassembly, TCP, checksum verification, or multi-interface PCAP.
"""
from __future__ import annotations
from dataclasses import dataclass
import ipaddress
from pathlib import Path
import struct
from typing import Iterator

class PacketFormatError(ValueError):
    pass

@dataclass(frozen=True)
class PcapFrame:
    timestamp_sec: int
    timestamp_fraction: int
    data: bytes
    original_length: int

@dataclass(frozen=True)
class UdpPacket:
    payload: bytes
    src_ip: str | None = None
    dst_ip: str | None = None
    src_port: int | None = None
    dst_port: int | None = None
    ordinal: int = 0

_MAGIC = {
    b'\xd4\xc3\xb2\xa1': ('<', 1_000_000),
    b'\xa1\xb2\xc3\xd4': ('>', 1_000_000),
    b'\x4d\x3c\xb2\xa1': ('<', 1_000_000_000),
    b'\xa1\xb2\x3c\x4d': ('>', 1_000_000_000),
}

def read_pcap(path: str | Path) -> Iterator[PcapFrame]:
    with open(path, 'rb') as f:
        header = f.read(24)
        if len(header) < 24:
            raise PacketFormatError('PCAP global header missing/truncated')
        if header[:4] == b'\x0a\x0d\x0d\x0a':
            raise PacketFormatError('pcapng not supported: convert with tshark -F pcap or Wireshark')
        if header[:4] not in _MAGIC:
            raise PacketFormatError('unrecognized classic PCAP magic')
        endian, resolution = _MAGIC[header[:4]]
        _, _, _, _, snaplen, linktype = struct.unpack(endian+'HHiIII', header[4:24])
        if linktype != 1:
            raise PacketFormatError(f'unsupported linktype={linktype}; Ethernet (DLT_EN10MB=1) required')
        if snaplen < 14 or snaplen > 16_777_216:
            raise PacketFormatError(f'invalid PCAP snaplen={snaplen}')
        number = 0
        while True:
            rec_header = f.read(16)
            if not rec_header:
                break
            if len(rec_header) != 16:
                raise PacketFormatError('truncated PCAP record header')
            ts_sec, ts_frac, cap_len, orig_len = struct.unpack(endian+'IIII', rec_header)
            number += 1
            if cap_len > snaplen or cap_len > orig_len:
                raise PacketFormatError(f'frame {number}: invalid capture length')
            data = f.read(cap_len)
            if len(data) != cap_len:
                raise PacketFormatError(f'frame {number}: truncated capture data')
            # PCAP writer emits microsecond records. Reduce nanosecond precision
            # only when reading nanosecond PCAP; payload bytes stay unchanged.
            if resolution == 1_000_000_000:
                ts_frac //= 1000
            yield PcapFrame(ts_sec, ts_frac, data, orig_len)

def write_pcap(path: str | Path, frames: list[PcapFrame]) -> None:
    """Write little-endian classic microsecond PCAP (timestamps as supplied)."""
    with open(path, 'wb') as f:
        f.write(b'\xd4\xc3\xb2\xa1')
        f.write(struct.pack('<HHiiii', 2, 4, 0, 0, 65535, 1))
        for frame in frames:
            f.write(struct.pack('<IIII', frame.timestamp_sec, frame.timestamp_fraction,
                                len(frame.data), frame.original_length))
            f.write(frame.data)

def extract_udp(frame: PcapFrame, ordinal: int = 0) -> UdpPacket | None:
    data = frame.data
    if len(data) < 14:
        raise PacketFormatError(f'frame {ordinal}: truncated Ethernet')
    ethertype = int.from_bytes(data[12:14], 'big')
    offset = 14
    vlan_count = 0
    while ethertype in (0x8100, 0x88a8, 0x9100):
        if len(data) < offset+4 or vlan_count >= 2:
            raise PacketFormatError(f'frame {ordinal}: invalid VLAN header')
        ethertype = int.from_bytes(data[offset+2:offset+4], 'big')
        offset += 4
        vlan_count += 1
    if ethertype != 0x0800:
        return None
    ip = data[offset:]
    if len(ip) < 20:
        raise PacketFormatError(f'frame {ordinal}: truncated IPv4 header')
    if ip[0] >> 4 != 4:
        raise PacketFormatError(f'frame {ordinal}: invalid IPv4 version')
    header_len = (ip[0] & 0xF) * 4
    total_len = int.from_bytes(ip[2:4], 'big')
    if header_len < 20 or len(ip) < header_len or total_len < header_len:
        raise PacketFormatError(f'frame {ordinal}: invalid IPv4 lengths')
    if total_len > len(ip):
        raise PacketFormatError(f'frame {ordinal}: truncated IPv4 packet (capture snaplen?)')
    if ip[9] != 17:
        return None
    flags_frag = int.from_bytes(ip[6:8], 'big')
    if flags_frag & 0x3FFF:
        raise PacketFormatError(f'frame {ordinal}: IPv4 fragmented UDP unsupported')
    body = ip[header_len:total_len]
    if len(body) < 8:
        raise PacketFormatError(f'frame {ordinal}: UDP header truncated')
    src_port, dst_port, udp_len, _ = struct.unpack('!HHHH', body[:8])
    if udp_len < 8 or udp_len > len(body):
        raise PacketFormatError(f'frame {ordinal}: invalid UDP length')
    return UdpPacket(payload=body[8:udp_len], src_ip=str(ipaddress.IPv4Address(ip[12:16])),
                     dst_ip=str(ipaddress.IPv4Address(ip[16:20])),
                     src_port=src_port, dst_port=dst_port, ordinal=ordinal)

def read_udp_pcap(path: str | Path) -> Iterator[UdpPacket]:
    for i, frame in enumerate(read_pcap(path), start=1):
        udp = extract_udp(frame, ordinal=i)
        if udp is not None:
            yield udp

def read_length_prefixed(path: str | Path, max_size: int = 65507) -> Iterator[UdpPacket]:
    """Four-byte big-endian length prefix plus payload, matching DIFI PC receiver.
    This format does NOT contain source IP/port or timestamps.
    """
    with open(path, 'rb') as f:
        i = 0
        while True:
            size_raw = f.read(4)
            if not size_raw:
                break
            if len(size_raw) != 4:
                raise PacketFormatError('truncated binary record length')
            size = struct.unpack('!I', size_raw)[0]
            if size > max_size:
                raise PacketFormatError(f'payload length {size} exceeds limit {max_size}')
            payload = f.read(size)
            if len(payload) != size:
                raise PacketFormatError('truncated binary payload')
            i += 1
            yield UdpPacket(payload=payload, ordinal=i)

def write_length_prefixed(path: str | Path, packets: list[bytes]) -> None:
    with open(path, 'wb') as f:
        for p in packets:
            if len(p) > 65507:
                raise ValueError('UDP payload too long')
            f.write(struct.pack('!I', len(p)))
            f.write(p)
