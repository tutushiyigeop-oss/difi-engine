#!/usr/bin/env python3
"""PC receiver/checker for B5 DIFI raw UDP export (Python 3 standard library)."""
import argparse
import socket
import struct
import time

NUM_DATA = 20
N_SAMPLES = 256
PORT = 4991
EXPECTED_SIZE = {5: 11, 4: 27, 1: 263}

def expected_iq(round_id: int, index: int) -> int:
    if index < 4:
        return [0x0001FFFF, 0x7FFF8000, 0xFFFE0003, 0x00000000][index]
    iv = (0x1000 + index + 0x200 * round_id) & 0xFFFF
    qv = (0xA000 + 3 * index + 0x11 * round_id) & 0xFFFF
    return (iv << 16) | qv

def check_packet(payload: bytes, seq_index: int):
    if not payload or len(payload) % 4:
        raise ValueError("payload is not an array of 32-bit DIFI words")
    words = struct.unpack(f"!{len(payload) // 4}I", payload)
    type_id = words[0] >> 28
    if seq_index == 0:
        expected_type, exp_seq, sid = 5, 0, 2
    elif seq_index == 1:
        expected_type, exp_seq, sid = 4, 0, 1
    else:
        expected_type, exp_seq, sid = 1, (seq_index - 2) % 16, 1
    if type_id != expected_type:
        raise ValueError(f"packet #{seq_index}: type {type_id} expected {expected_type}")
    expected_words = EXPECTED_SIZE[type_id]
    if len(words) != expected_words or (words[0] & 0xFFFF) != expected_words:
        raise ValueError(f"packet #{seq_index}: length error, got {len(words)} / declared {words[0] & 0xFFFF}")
    head = (type_id << 28) | 0x08600000 | (exp_seq << 16) | expected_words
    if type_id != 1: head |= 0x01000000
    if words[0] != head:
        raise ValueError(f"packet #{seq_index}: header 0x{words[0]:08x} != 0x{head:08x}")
    if words[1] != sid or words[2] != 0x006A621E:
        raise ValueError(f"packet #{seq_index}: Stream ID or OUI mismatch")
    if type_id == 1:
        if words[3] != 0:
            raise ValueError(f"packet #{seq_index}: bad Data Class ID")
        round_id = seq_index - 2
        for i, word in enumerate(words[7:]):
            expect = expected_iq(round_id, i)
            if word != expect:
                raise ValueError(f"Data round={round_id} sample={i}: 0x{word:08x} != 0x{expect:08x}")
    elif type_id == 5:
        if words[3] != 0x00010004 or words[7] != 0x80000002:
            raise ValueError("Version fields mismatch")
    elif type_id == 4:
        if words[3] != 0x00000001 or words[7] != 0xFBB98000 or words[25] != 0xA00003CF:
            raise ValueError("Context fields mismatch")
    return type_id, exp_seq, len(words), len(words) * 4

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--board", default="192.168.1.10", help="Zynq board IP")
    ap.add_argument("--port", type=int, default=PORT)
    ap.add_argument("--pc-ip", default="0.0.0.0", help="Local bind IP; default all interfaces")
    ap.add_argument("--timeout", type=float, default=10.0, help="Timeout for each packet, seconds")
    ap.add_argument("--output", default="difi_udp_capture.bin", help="Save concatenated length-prefixed UDP payloads")
    args = ap.parse_args()
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((args.pc_ip, args.port))
    sock.settimeout(args.timeout)
    print(f"[INFO] UDP listening on {args.pc_ip}:{args.port}")
    print(f"[INFO] sending START to {args.board}:{args.port}")
    sock.sendto(b"START", (args.board, args.port))
    bytes_data = 0
    total = 2 + NUM_DATA
    t0 = time.monotonic()
    with open(args.output, "wb") as file:
        for i in range(total):
            try:
                data, (sender, source_port) = sock.recvfrom(4096)
            except socket.timeout:
                raise SystemExit(f"[FAIL] timeout waiting packet #{i}; received {i}/{total}. Check board UART, PC IP/firewall.")
            if sender != args.board:
                raise SystemExit(f"[FAIL] unexpected sender {sender} (board should be {args.board})")
            try:
                typ, seq, length, nbytes = check_packet(data, i)
            except ValueError as e:
                raise SystemExit(f"[FAIL] {e}")
            bytes_data += nbytes
            file.write(struct.pack("!I", len(data)))
            file.write(data)
            print(f"[PASS] #{i:02d} type={typ} seq={seq:2d} words={length:3d} bytes={nbytes:4d}")
    dt = time.monotonic() - t0
    print(f"[PASS] DIFI UDP full chain: 1 Version + 1 Context + {NUM_DATA} Data, {NUM_DATA * N_SAMPLES} IQ correct")
    print(f"[INFO] captured {bytes_data} UDP payload bytes in {dt:.3f}s; saved to {args.output}")
    print("[NOTE] Deliberate 2ms per-packet pacing; this is NOT a UDP throughput benchmark.")

if __name__ == "__main__":
    main()
