#!/usr/bin/env python3
"""Send deterministic DIFI v1.1 Data packets to B6 Zynq UDP RX.

No third-party dependencies. Generates exactly the same B5 test IQ pattern.
Packet format: big-endian network words, 7-word header + 256 I16/Q16.
Board replies READY NEXT_ROUND=n, then ACK PASS ROUND=n SEQ=n%16 IQ=256.
This is an acceptance client, not a network speed benchmark.
"""
import argparse
import socket
import struct

SAMPLES = 256
HEADER_WORDS = 7
WORDS = HEADER_WORDS + SAMPLES
DATA_SID = 1
OUI = 0x006A621E
EDGE = [0x0001FFFF, 0x7FFF8000, 0xFFFE0003, 0x00000000]


def expected_iq(round_id: int, index: int) -> int:
    if not 0 <= index < SAMPLES:
        raise ValueError("sample index out of range")
    if index < 4:
        return EDGE[index]
    iv = (0x1000 + index + 0x200 * round_id) & 0xFFFF
    qv = (0xA000 + 3 * index + 0x11 * round_id) & 0xFFFF
    return (iv << 16) | qv


def make_packet(round_id: int, time_sec: int = 1_700_000_000, time_ps: int = 0) -> bytes:
    if not 0 <= round_id <= 0xFFFFFFFF:
        raise ValueError("round_id must be uint32")
    if not 0 <= time_sec <= 0xFFFFFFFF or not 0 <= time_ps <= 0xFFFFFFFFFFFFFFFF:
        raise ValueError("timestamp out of range")
    word0 = 0x18600107 | ((round_id & 15) << 16)
    words = [word0, DATA_SID, OUI, 0, time_sec, (time_ps >> 32) & 0xFFFFFFFF,
             time_ps & 0xFFFFFFFF]
    words.extend(expected_iq(round_id, i) for i in range(SAMPLES))
    payload = struct.pack("!" + str(len(words)) + "I", *words)
    assert len(words) == WORDS and len(payload) == WORDS * 4
    return payload


def _receive(sock: socket.socket, endpoint: tuple[str, int]) -> str:
    data, addr = sock.recvfrom(2048)
    if addr != endpoint:
        raise RuntimeError(f"Unexpected responder {addr}, expected {endpoint}")
    return data.decode("ascii", errors="replace").strip()


def send_packets(board: str, port: int, local_ip: str, timeout: float,
                 rounds: int, dry_run: bool, start_round: int | None) -> int:
    if rounds < 1 or rounds > 1000:
        raise ValueError("--rounds must be 1..1000")
    if dry_run:
        start = start_round if start_round is not None else 0
        for r in range(start, start + rounds):
            packet = make_packet(r)
            print(f"[DRY] round={r} seq={r & 15} bytes={len(packet)}"
                  f" header=0x{int.from_bytes(packet[:4], 'big'):08X}")
        print("[DRY] No hardware communication was performed")
        return 0
    endpoint = (socket.gethostbyname(board), port)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind((local_ip, 0))
        sock.settimeout(timeout)
        sock.sendto(b"STATUS", endpoint)
        status = _receive(sock, endpoint)
        print("[BOARD]", status)
        if not status.startswith("READY NEXT_ROUND="):
            raise RuntimeError("Board did not return B6 READY; wrong ELF or port?")
        try:
            expected = int(status.split("NEXT_ROUND=", 1)[1].split()[0])
        except (IndexError, ValueError) as exc:
            raise RuntimeError("Malformed READY reply") from exc
        if start_round is not None and start_round != expected:
            raise RuntimeError(f"Board expects round {expected}, but --start-round={start_round}.")
        start = expected
        for r in range(start, start + rounds):
            packet = make_packet(r)
            sock.sendto(packet, endpoint)
            response = _receive(sock, endpoint)
            target = f"ACK PASS ROUND={r} SEQ={r & 15} IQ=256"
            if response != target:
                print(f"[FAIL] round={r}: {response}")
                return 1
            print(f"[PASS] round={r:03d} seq={r & 15:02d} input=1052B output=1024B IQ=256")
    print(f"[PASS] B6 PC -> UDP -> FPGA RX -> DDR: {rounds} packets; {rounds*SAMPLES} IQ validated")
    print("[NOTE] Per-packet ACK, not a UDP bandwidth benchmark")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--board", default="192.168.1.10", help="B6 board IP")
    ap.add_argument("--port", type=int, default=4991)
    ap.add_argument("--local-ip", default="0.0.0.0", help="PC interface bind IP")
    ap.add_argument("--timeout", type=float, default=5.0, help="timeout for each ACK, seconds")
    ap.add_argument("--rounds", type=int, default=1, help="number of Data packets, max 1000")
    ap.add_argument("--start-round", type=int, default=None, help="assert expected round; normally query board")
    ap.add_argument("--dry-run", action="store_true", help="generate packets without any network I/O")
    args = ap.parse_args()
    try:
        return send_packets(args.board, args.port, args.local_ip,
                            args.timeout, args.rounds, args.dry_run, args.start_round)
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"[FAIL] {exc}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
