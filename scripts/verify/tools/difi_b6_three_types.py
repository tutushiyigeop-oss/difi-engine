#!/usr/bin/env python3
"""B6 v0.2: PC -> UDP -> FPGA RX, validate VERSION + CONTEXT + DATA.

Keep the existing difi_b6_sender.py for backwards-compatible DATA-only tests.
The FPGA board must run B6 v0.2 XSA / main.c / AXI-GPIO metadata monitor.
"""
import argparse
import socket
import struct

from difi_b6_sender import make_packet as make_data_packet

BOARD_DEFAULT = '192.168.1.10'


def pack_words(words: list[int]) -> bytes:
    assert all(0 <= n <= 0xffffffff for n in words)
    return struct.pack('!' + str(len(words)) + 'I', *words)


def version_packet(count: int, seconds: int = 1_700_000_000) -> bytes:
    """Match rtl/version/difi_version_generator.v and difi_v1_1_defs.vh."""
    if count < 0:
        raise ValueError('version count must be nonnegative')
    seq = count & 15
    cif0 = 0x80000002 if count == 0 else 0x00000002
    # BUILD_YEAR_OFFSET=26; BUILD_DAY_OF_YEAR=252; REVISION=1, TYPE=0, ICD=0.
    version_info = (26 << 25) | (252 << 16) | (1 << 10)
    words = [0x5960000B | (seq << 16), 2, 0x006A621E, 0x00010004,
             seconds, 0, 0, cif0, 0x0000000C, 0x00000004, version_info]
    return pack_words(words)


def context_packet(count: int, seconds: int = 1_700_000_000,
                   sample_rate: int = 20_000_000,
                   bandwidth: int = 10_000_000,
                   rf_hz: int = 100_000_000) -> bytes:
    """Match rtl/context/difi_context_generator.v (B5 test settings)."""
    if count < 0:
        raise ValueError('context count must be nonnegative')
    if not 0 < bandwidth <= sample_rate <= 0xffffffff or not 0 <= rf_hz <= 100_000_000_000:
        raise ValueError('context field outside parser constraints')
    seq = count & 15
    cif0 = 0xFBB98000 if count == 0 else 0x7BB98000
    words = [0] * 27
    words[:9] = [0x4960001B | (seq << 16), 1, 0x006A621E, 1,
                 seconds, 0, 0, cif0, 100]
    bw = bandwidth << 20
    rf = rf_hz << 20
    fs = sample_rate << 20
    words[9], words[10] = (bw >> 32) & 0xffffffff, bw & 0xffffffff
    words[13], words[14] = (rf >> 32) & 0xffffffff, rf & 0xffffffff
    words[19], words[20] = (fs >> 32) & 0xffffffff, fs & 0xffffffff
    words[25], words[26] = 0xA00003CF, 0
    return pack_words(words)


def parse_status(message: str) -> dict[str, int]:
    if not message.startswith('READY '):
        raise RuntimeError(f'Unexpected board STATUS: {message}')
    result = {}
    for part in message.split()[1:]:
        if '=' in part:
            name, value = part.split('=', 1)
            result[name] = int(value)
    for key in ('NEXT_ROUND', 'NEXT_VERSION', 'NEXT_CONTEXT'):
        if key not in result:
            raise RuntimeError(f'Board STATUS missing {key}; wrong ELF?')
    return result


def _recv(sock: socket.socket, endpoint: tuple[str, int]) -> str:
    response, address = sock.recvfrom(2048)
    if address != endpoint:
        raise RuntimeError(f'Unexpected UDP sender: {address}')
    return response.decode('ascii', errors='replace').strip()


def run(board: str, local_ip: str, port: int, timeout: float,
        types: list[str], rounds: int, dry_run: bool) -> int:
    if rounds < 1 or rounds > 1000:
        raise ValueError('--rounds must be 1..1000')
    if dry_run:
        v = 0
        c = 0
        d = 0
    else:
        endpoint = (socket.gethostbyname(board), port)
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            sock.bind((local_ip, 0))
            sock.settimeout(timeout)
            sock.sendto(b'STATUS', endpoint)
            status = _recv(sock, endpoint)
            print('[BOARD]', status)
            stat = parse_status(status)
            v, c, d = stat['NEXT_VERSION'], stat['NEXT_CONTEXT'], stat['NEXT_ROUND']
        except Exception:
            sock.close()
            raise
    try:
        for typ in types:
            if typ == 'version':
                payload = version_packet(v)
                expected = f'ACK PASS TYPE=VERSION SEQ={v & 15} META=1'
                v += 1
                items = [('version', payload, expected)]
            elif typ == 'context':
                payload = context_packet(c)
                expected = f'ACK PASS TYPE=CONTEXT SEQ={c & 15} META=1'
                c += 1
                items = [('context', payload, expected)]
            elif typ == 'data':
                items = [('data', make_data_packet(r),
                          f'ACK PASS ROUND={r} SEQ={r & 15} IQ=256')
                         for r in range(d, d + rounds)]
                d += rounds
            else:
                raise ValueError(f'unsupported type {typ}')
            for kind, data, expected in items:
                header = int.from_bytes(data[:4], 'big')
                if dry_run:
                    print(f'[DRY] {kind.upper()} bytes={len(data)} word0=0x{header:08X}')
                    continue
                sock.sendto(data, endpoint)
                ack = _recv(sock, endpoint)
                if ack != expected:
                    print(f'[FAIL] {kind}: {ack} (expected {expected})')
                    return 1
                print(f'[PASS] {kind.upper():7s} bytes={len(data):4d} {ack}')
    finally:
        if not dry_run:
            sock.close()
    if dry_run:
        print('[DRY] No UDP transmitted')
    else:
        print('[PASS] Selected B6 packet types validated by the board')
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--board', default=BOARD_DEFAULT)
    ap.add_argument('--local-ip', default='192.168.1.20')
    ap.add_argument('--port', type=int, default=4991)
    ap.add_argument('--timeout', type=float, default=5.)
    ap.add_argument('--types', default='version,context,data',
                    help='comma separated order: version,context,data')
    ap.add_argument('--rounds', type=int, default=20,
                    help='number of DATA packets if --types includes data')
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()
    types = [x.strip().lower() for x in args.types.split(',') if x.strip()]
    if not types or len(set(types)) != len(types) or any(
            typ not in ('version', 'context', 'data') for typ in types):
        ap.error('--types expects unique subset of version,context,data')
    try:
        return run(args.board, args.local_ip, args.port,
                   args.timeout, types, args.rounds, args.dry_run)
    except (OSError, RuntimeError, ValueError) as exc:
        print(f'[FAIL] {exc}')
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
