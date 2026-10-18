"""Windows / Python 3 UDP Echo functional test for the Zynq PS GEM0 example."""
import argparse
import socket
import time


def main():
    parser = argparse.ArgumentParser(description="PC <-> Zynq UDP Echo test")
    parser.add_argument("--local-ip", default="192.168.1.20",
                        help="PC wired Ethernet IPv4 (use 0.0.0.0 for auto)")
    parser.add_argument("--board-ip", default="192.168.1.10")
    parser.add_argument("--port", type=int, default=4991)
    parser.add_argument("--timeout", type=float, default=3.0)
    args = parser.parse_args()

    vectors = [
        ("hello", b"Hello Zynq"),
        ("44-byte frame", bytes(range(44))),
        ("108-byte frame", bytes(range(108))),
        ("1052-byte frame", bytes(i % 256 for i in range(1052))),
    ]

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.settimeout(args.timeout)
        sock.bind((args.local_ip, 0))
        print("PC local   :", sock.getsockname())
        print("Zynq target:", (args.board_ip, args.port))

        for name, payload in vectors:
            start = time.perf_counter()
            sock.sendto(payload, (args.board_ip, args.port))
            try:
                received, sender = sock.recvfrom(2048)
            except socket.timeout:
                print(f"[TIMEOUT] {name}: Zynq did not reply within {args.timeout}s")
                return 1
            elapsed_ms = (time.perf_counter() - start) * 1000.0
            ok = (received == payload and
                  sender[0] == args.board_ip and sender[1] == args.port)
            print(f"[{'PASS' if ok else 'FAIL'}] {name}: {len(payload)} B, "
                  f"round-trip={elapsed_ms:.2f} ms, from={sender}")
            if not ok:
                print("Mismatch: reply differs from sent payload or endpoint")
                return 1

    print("\nALL 4 UDP ECHO TESTS PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
