#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""B5 UART capture (.rtf or .txt/.log) -> raw DIFI .bin + split-flow UDP PCAPs.

Only Python standard library is required; Python 3.8+.

Example:
    python rtf_to_pcap.py "MobaXterm_session.rtf"
    python rtf_to_pcap.py session.rtf --out verification/pcap
    python rtf_to_pcap.py session.log --dst-port 4991

PCAPs contain SYNTHETIC Ethernet/IPv4/UDP headers around REAL FPGA DIFI
32-bit words. The script writes the original combined capture, plus separate
Version Flow and Data/Context Flow PCAPs, grouped by 32-bit Stream ID. This is an OFFLINE packet-format test, NOT a real network capture,
nor proof of Zynq Ethernet UDP delivery or official DIFI certification.
"""

import argparse
import ipaddress
from pathlib import Path
import re
import struct
import sys
import time

START_MARKER = "[B5_START]"
END_MARKER = "[B5_END]"
WORD_RE = re.compile(r"^W\s*\[\s*(\d+)\s*\]\s*=\s*(?:0[xX])?([0-9A-Fa-f]{8})\s*$")
TYPE_NAMES = {1: "data", 4: "context", 5: "version"}
RTF_SKIP_GROUPS = {
    "fonttbl", "colortbl", "stylesheet", "info", "pict", "object", "filetbl",
    "listtable", "listoverridetable", "revtbl", "generator", "themedata",
    "colorschememapping", "datastore", "xmlnstbl", "rsidtbl", "fldinst",
}

def strip_rtf(raw: bytes) -> str:
    """Decode ordinary MobaXterm/Windows RTF with no nonstdlib dependencies.

    Handles RTF groups, destinations, paragraphs, control words, escaped
    backslashes/braces, \\'hh bytes and \\uN Unicode escapes. Rich formatting
    is discarded, while serial-console text and its line breaks are preserved.
    """
    s = raw.decode("latin-1")
    cp = re.search(r"\\ansicpg(\d+)", s[:8192])
    encoding = "cp" + cp.group(1) if cp else "cp1252"
    try:
        "".encode(encoding)
    except LookupError:
        encoding = "cp1252"

    chunks = []
    chars = bytearray()
    stack = [{"skip": False, "uc": 1}]
    skip_fallback = 0
    i = 0

    def flush():
        if chars:
            chunks.append(bytes(chars).decode(encoding, errors="replace"))
            chars.clear()

    while i < len(s):
        c = s[i]
        if c == "{":
            flush()
            stack.append(stack[-1].copy())
            i += 1
            continue
        if c == "}":
            flush()
            if len(stack) > 1:
                stack.pop()
            i += 1
            continue
        if c != "\\":
            i += 1
            if c in "\r\n":  
                continue
            if skip_fallback:
                skip_fallback -= 1
                continue
            if not stack[-1]["skip"]:
                chars.append(ord(c))
            continue

        i += 1
        if i >= len(s):
            break
        sym = s[i]
        if sym in "\\{}":
            i += 1
            if skip_fallback:
                skip_fallback -= 1
            elif not stack[-1]["skip"]:
                chars.append(ord(sym))
            continue
        if sym == "'":
            if i + 2 >= len(s) or not re.fullmatch(r"[0-9a-fA-F]{2}", s[i + 1:i + 3]):
                raise ValueError("RTF malformed \\'hh byte escape")
            val = int(s[i + 1:i + 3], 16)
            i += 3
            if skip_fallback:
                skip_fallback -= 1
            elif not stack[-1]["skip"]:
                chars.append(val)
            continue
        if not sym.isalpha():
            i += 1
            if sym == "*":
                stack[-1]["skip"] = True
            elif not stack[-1]["skip"]:
                if sym == "~":
                    chars.append(32)
                elif sym in ("-", "_"):
                    chars.append(45)
            continue

        start = i
        while i < len(s) and s[i].isalpha():
            i += 1
        word = s[start:i]
        sign_start = i
        if i < len(s) and s[i] == "-":
            i += 1
        while i < len(s) and s[i].isdigit():
            i += 1
        arg = int(s[sign_start:i]) if i > sign_start and s[sign_start:i] != "-" else None
        if i < len(s) and s[i] == " ":
            i += 1

        if word in RTF_SKIP_GROUPS:
            stack[-1]["skip"] = True
        if stack[-1]["skip"]:
            continue
        if word in ("par", "line", "row"):
            flush()
            chunks.append("\n")
        elif word == "tab":
            chars.append(9)
        elif word == "uc" and arg is not None:
            stack[-1]["uc"] = max(0, arg)
        elif word == "u" and arg is not None:
            flush()
            u = arg & 0xFFFF
            
            chunks.append(chr(u))
            skip_fallback = stack[-1]["uc"]
        elif word == "emdash":
            flush()
            chunks.append("\u2014")
        elif word == "endash":
            flush()
            chunks.append("\u2013")

    flush()
    return "".join(chunks)

def load_console_text(path: Path) -> str:
    raw = path.read_bytes()
    if raw.lstrip().startswith(b"{\\rtf"):
        return strip_rtf(raw)
    
    for enc in ("utf-8-sig", "gb18030", "cp1252"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", errors="replace")

def extract_packets(text: str):
    packets = []
    block = None
    for line_no, raw_line in enumerate(text.splitlines(), start=1):
        line = raw_line.strip().lstrip("\ufeff")
        if START_MARKER in line:
            if block is not None:
                raise ValueError(f"line {line_no}: nested {START_MARKER}")
            block = []
            continue
        if END_MARKER in line:
            if block is None:
                raise ValueError(f"line {line_no}: {END_MARKER} without start marker")
            if not block:
                raise ValueError(f"line {line_no}: empty packet capture")
            packets.append(block)
            block = None
            continue
        if block is None or not line:
            continue
        match = WORD_RE.fullmatch(line)
        if not match:
            raise ValueError(f"line {line_no}: invalid line inside packet: {line!r}")
        word_index = int(match.group(1))
        if word_index != len(block):
            raise ValueError(
                f"line {line_no}: expected W[{len(block):03d}] but found W[{word_index:03d}]"
            )
        block.append(int(match.group(2), 16))
    if block is not None:
        raise ValueError(f"missing {END_MARKER} at end of capture")
    if not packets:
        raise ValueError("No B5 packet blocks found. Check whether the RTF contains [B5_START]/[B5_END].")
    return packets

def packet_to_bytes(words, number):
    packet_type = (words[0] >> 28) & 0xF
    size_words = words[0] & 0xFFFF
    if size_words != len(words):
        raise ValueError(
            f"packet #{number}: Word0 Packet Size={size_words}, "
            f"but captured {len(words)} words"
        )
    if packet_type not in TYPE_NAMES:
        raise ValueError(f"packet #{number}: unexpected DIFI Packet Type=0x{packet_type:X}")
    if packet_type == 4 and len(words) != 27:
        raise ValueError(f"packet #{number}: Context should have 27 Words, got {len(words)}")
    if packet_type == 5 and len(words) != 11:
        raise ValueError(f"packet #{number}: Version should have 11 Words, got {len(words)}")
    if packet_type == 1 and not (8 <= len(words) <= 263):
        raise ValueError(f"packet #{number}: Data should have 7+N Words, N in 1..256")
    # Write UART words to UDP in big-endian order, e.g. 5960000B -> 59 60 00 0B.
    
    payload = b"".join(struct.pack("!I", w) for w in words)
    return packet_type, payload

def checksum16(data: bytes) -> int:
    if len(data) % 2:
        data += b"\x00"
    total = sum(struct.unpack("!" + "H" * (len(data) // 2), data))
    while total >> 16:
        total = (total & 0xFFFF) + (total >> 16)
    return (~total) & 0xFFFF

def ethernet_ipv4_udp(payload, *, number, src_ip, dst_ip, src_port, dst_port):
    src_ip_raw = ipaddress.IPv4Address(src_ip).packed
    dst_ip_raw = ipaddress.IPv4Address(dst_ip).packed
    udp_len = 8 + len(payload)
    ip_len = 20 + udp_len
    if ip_len > 65535:
        raise ValueError("Payload too large for single IPv4 datagram")

    ip_no_checksum = struct.pack(
        "!BBHHHBBH4s4s", 0x45, 0, ip_len, (number + 1) & 0xFFFF,
        0x0000, 64, 17, 0, src_ip_raw, dst_ip_raw,
    )
    ip_header = (ip_no_checksum[:10] + struct.pack("!H", checksum16(ip_no_checksum))
                 + ip_no_checksum[12:])
    udp_zero_checksum = struct.pack("!HHHH", src_port, dst_port, udp_len, 0)
    pseudo_header = src_ip_raw + dst_ip_raw + struct.pack("!BBH", 0, 17, udp_len)
    udp_checksum = checksum16(pseudo_header + udp_zero_checksum + payload)
    if udp_checksum == 0:
        udp_checksum = 0xFFFF
    udp_header = struct.pack("!HHHH", src_port, dst_port, udp_len, udp_checksum)
    
    ethernet_header = bytes.fromhex("0200000000020200000000010800")
    return ethernet_header + ip_header + udp_header + payload

def write_pcap(path: Path, records):
    """Write pre-built (timestamp seconds, Ethernet frame) pairs in PCAP format."""
    with path.open("wb") as f:
        
        f.write(struct.pack("<IHHIIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, 1))
        for ts_sec, frame in records:
            f.write(struct.pack("<IIII", ts_sec, 0, len(frame), len(frame)))
            f.write(frame)

def write_outputs(packets, output: Path, args):
    
    validated = [packet_to_bytes(words, i) for i, words in enumerate(packets)]
    output.mkdir(parents=True, exist_ok=True)

    # Do not merge Context and Data packets with different Stream IDs.
    flow_records = {}
    all_records = []
    seconds = int(time.time())  # Capture timestamps are generated, not FPGA timestamps.

    for index, (words, (type_code, payload)) in enumerate(zip(packets, validated)):
        name = TYPE_NAMES[type_code]
        stream_id = words[1]  
        flow_name = "version" if type_code == 5 else "data_context"
        key = (flow_name, stream_id)
        binary_path = output / f"packet_{index:02d}_{name}.bin"
        binary_path.write_bytes(payload)

        frame = ethernet_ipv4_udp(
            payload, number=index, src_ip=args.src_ip,
            dst_ip=args.dst_ip, src_port=args.src_port, dst_port=args.dst_port,
        )
        record = (seconds + index, frame)
        all_records.append(record)
        flow_records.setdefault(key, []).append(record)
        print(f"[OK] #{index} {name:<7} SID=0x{stream_id:08X} | "
              f"{len(words):3d} Words | {len(payload):4d} bytes | "
              f"Word0={words[0]:08X} | {binary_path.name}")

    combined_path = output / "b5_synthetic_udp.pcap"
    write_pcap(combined_path, all_records)
    print(f"\n[OUTPUT] Combined (original order): {combined_path.resolve()} "
          f"({len(all_records)} packets)")

    category_count = {}
    for flow_name, _ in flow_records:
        category_count[flow_name] = category_count.get(flow_name, 0) + 1

    for (flow_name, stream_id), records in flow_records.items():
        stem = f"b5_{flow_name}_flow"
        if category_count[flow_name] != 1:
            stem += f"_sid_{stream_id:08X}"
        split_path = output / (stem + ".pcap")
        write_pcap(split_path, records)
        print(f"[FLOW] {flow_name:<12} SID=0x{stream_id:08X} | "
              f"{len(records)} packet(s) | {split_path.resolve()}")

    print("[NOTE] Flow grouping: Version independent; Context/Data grouped ONLY with matching Stream ID.")
    print("[NOTE] Original 32-bit DIFI words and packet order are unchanged; split PCAPs use subsets.")
    print("[NOTE] Ethernet/IPv4/UDP headers and PCAP arrival times are SYNTHETIC (offline validation).")
    print("[NOTE] A PASS on split flows is not a PASS on the combined capture or formal certification.")
    return combined_path

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("input", type=Path, help="MobaXterm .rtf, or plain .log/.txt UART capture")
    parser.add_argument("--out", type=Path, default=Path("b5_export"), help="Output folder (default: b5_export)")
    parser.add_argument("--dst-port", type=int, default=4991, help="Synthetic destination UDP port (default: 4991)")
    parser.add_argument("--src-port", type=int, default=4991, help="Synthetic source UDP port (default: 4991)")
    parser.add_argument("--src-ip", default="192.0.2.1", help="Synthetic source IPv4 address")
    parser.add_argument("--dst-ip", default="192.0.2.2", help="Synthetic destination IPv4 address")
    args = parser.parse_args(argv)
    try:
        if not args.input.is_file():
            raise ValueError(f"Cannot read input file: {args.input}")
        for port in (args.src_port, args.dst_port):
            if not (1 <= port <= 65535):
                raise ValueError("UDP ports must be in the range 1..65535")
        ipaddress.IPv4Address(args.src_ip)
        ipaddress.IPv4Address(args.dst_ip)
        text = load_console_text(args.input)
        packets = extract_packets(text)
        print(f"[INPUT] {args.input}: detected {len(packets)} packet(s)")
        write_outputs(packets, args.out, args)
        return 0
    except (ValueError, OSError, UnicodeError) as ex:
        print(f"[ERROR] {ex}", file=sys.stderr)
        return 1

if __name__ == "__main__":
    sys.exit(main())
