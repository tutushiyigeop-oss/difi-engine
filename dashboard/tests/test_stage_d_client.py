"""SOFTWARE UDP SIMULATOR tests. Every datagram stays on 127.0.0.1."""
import socket
import struct
import threading

import pytest

from dashboard.app.experiment.client import (StageDClient, StageDError, HEADER, MAGIC,
    CAPS, OPEN, CONFIG, UTC, TX, RX, STATUS, CLOSE, PACKET, IQ, DONE, legacy_iq)
from dashboard.app.experiment.profile import ProfileConfig, build_packet, parse_packet, encode_iq, decode_iq, decode_config


class BoardSimulator:
    """Explicit fake board; not a hardware test or a claim about FPGA execution."""
    def __init__(self, version=3, start_round=0, duplicate=False, conflict=False, silence=False, ack_fail=False, done_first=False, late_conflict=False):
        self.version, self.tx_round, self.rx_round = version, start_round, start_round
        self.duplicate, self.conflict, self.silence, self.ack_fail = duplicate, conflict, silence, ack_fail
        self.done_first, self.late_conflict = done_first, late_conflict
        self.utc, self.pending, self.rx_step = 0, 0, 0
        self.config = ProfileConfig()
        self.requests, self.peers, self.errors = [], [], []
        self.session, self.next = 0, {"DATA": start_round, "CONTEXT": 0, "VERSION": 0}
        self.rx_next = {"DATA": start_round, "CONTEXT": 0, "VERSION": 0}
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(("127.0.0.1", 0))
        self.port = self.sock.getsockname()[1]
        self.sock.settimeout(.05)
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self._serve, daemon=True)
        self.thread.start()

    def close(self):
        self.stop.set()
        self.thread.join(timeout=1)
        self.sock.close()
        assert not self.errors, self.errors

    def send(self, raw, peer):
        self.sock.sendto(raw, peer)

    def status(self):
        if self.version == 3:
            return f"STATUS MODE=0 UTC={self.utc} TX={self.tx_round} RX={self.rx_round} PENDING={self.pending} STEP={self.rx_step} MON=00010001 ENGINE=00000010".encode()
        return (f"STATUS PROTO=4 STATE=READY UTC={self.utc} SESSION={self.session} " +
                " ".join(f"NEXT_{key}={value}" for key, value in self.next.items()) + " " +
                " ".join(f"RX_{key}_NEXT={value}" for key, value in self.rx_next.items())).encode()

    def frame(self, opcode, body, peer, sid, txid):
        if isinstance(body, str):
            body = body.encode()
        self.send(HEADER.pack(MAGIC, 4, opcode, 0, sid, txid, len(body), 0) + body, peer)

    def _serve(self):
        while not self.stop.is_set():
            try:
                raw, peer = self.sock.recvfrom(65535)
            except socket.timeout:
                continue
            except OSError:
                return
            self.requests.append(raw)
            self.peers.append(peer)
            if self.silence:
                continue
            try:
                self._handle(raw, peer)
            except Exception as exc:
                self.errors.append(str(exc))

    def _handle(self, raw, peer):
        if raw == b"STATUS":
            self.send(self.status(), peer)
            return
        if self.version == 4:
            return self._v4(raw, peer)
        if raw.startswith(b"UTC "):
            self.utc = 1
            self.send(b"OK UTC ENGINE_READY", peer)
        elif raw == b"TX":
            kinds = ["VERSION", "CONTEXT", "DATA"] if self.tx_round == 0 else ["DATA"]
            for kind in kinds:
                packet = build_packet(kind, self.config, legacy_iq(self.tx_round) if kind == "DATA" else None,
                                      sequence=self.tx_round & 15 if kind == "DATA" else 0)
                self.send(packet, peer)
                if self.duplicate:
                    self.send(packet, peer)
            self.send(f"TXDONE SEQ={self.tx_round & 15} IQ=256 PACKETS={len(kinds)}".encode(), peer)
            self.tx_round += 1
            self.pending = 1
        elif raw == b"RX":
            self.rx_step = 0 if self.rx_round == 0 else 2
            self.send(b"READY RX VERSION" if self.rx_step == 0 else b"READY RX DATA", peer)
        else:
            parsed = parse_packet(raw)
            kind = parsed["packet_type"]
            if self.ack_fail:
                self.send(b"ACK FAIL FPGA_IQ", peer)
            elif kind != "DATA":
                self.send(f"ACK PASS TYPE={kind} META=1".encode(), peer)
                self.rx_step += 1
            else:
                self.send(b"IQD3" + encode_iq(parsed["iq"]), peer)
                self.send(f"ACK PASS TYPE=DATA SEQ={parsed['sequence']} IQ=256".encode(), peer)
                self.pending = 0
                self.rx_round += 1

    def _v4(self, raw, peer):
        magic, ver, opcode, flags, sid, txid, length, code = HEADER.unpack_from(raw)
        assert magic == MAGIC and ver == 4 and flags == code == 0 and length == len(raw) - HEADER.size
        body = raw[HEADER.size:]
        if opcode == CAPS:
            response = "PROTO=4 MIN_SAMPLES=1 MAX_SAMPLES=256 CUSTOM_TX=1 CUSTOM_RX=1 CONFIG=1"
        elif opcode == OPEN:
            self.session = sid
            response = self.status().decode().removeprefix("STATUS ")
        elif opcode == CONFIG:
            self.config = decode_config(body)
            c = self.config
            response = (f"STATE=READY DATA_SID={c.data_sid} VERSION_SID={c.version_sid} SAMPLES={c.samples} "
                        f"FS={c.sample_rate} BW={c.bandwidth} RF_HZ={c.rf_hz} RX_FILTER={c.rx_filter} "
                        f"RX_DATA_SID={c.rx_data_sid} RX_VERSION_SID={c.rx_version_sid}")
        elif opcode == UTC:
            assert len(body) == 8
            self.utc = 1
            response = "STATE=READY UTC=1"
        elif opcode == STATUS:
            response = self.status().decode().removeprefix("STATUS ")
        elif opcode == CLOSE:
            self.session = 0
            response = "STATE=READY SESSION=0"
        elif opcode == TX:
            iq = decode_iq(body)
            kinds = ["VERSION", "CONTEXT", "DATA"] if self.next["DATA"] == 0 else ["DATA"]
            done = f"STATE=READY TYPE=DATA SEQ={self.next['DATA'] & 15} SAMPLES={len(iq)} PACKETS={len(kinds)}"
            if self.done_first:
                self.frame(DONE, done, peer, sid, txid)
            for kind in kinds:
                packet = build_packet(kind, self.config, iq if kind == "DATA" else None,
                                      sequence=self.next[kind] & 15)
                # A late transaction is never accepted as current evidence.
                self.frame(PACKET, packet, peer, sid, txid - 1)
                self.frame(PACKET, packet, peer, sid, txid)
                if self.duplicate:
                    self.frame(PACKET, packet, peer, sid, txid)
                if self.conflict and kind == "DATA":
                    bad = packet[:-1] + bytes([packet[-1] ^ 1])
                    self.frame(PACKET, bad, peer, sid, txid)
                self.next[kind] += 1
            if not self.done_first:
                self.frame(DONE, done, peer, sid, txid)
            if self.late_conflict:
                self.frame(PACKET, packet[:-1] + bytes([packet[-1] ^ 1]), peer, sid, txid)
            return
        elif opcode == RX:
            parsed = parse_packet(body, self.config)
            kind, seq = parsed["packet_type"], parsed["sequence"]
            self.rx_next[kind] += 1
            done = f"STATE=READY TYPE={kind} SEQ={seq} SAMPLES={len(parsed['iq'])} PACKETS=1 META=1"
            if self.done_first:
                self.frame(DONE, done, peer, sid, txid)
            if kind == "DATA":
                self.frame(IQ, encode_iq(parsed["iq"]), peer, sid, txid)
            if not self.done_first:
                self.frame(DONE, done, peer, sid, txid)
            return
        else:
            raise AssertionError(opcode)
        self.frame(opcode | 0x80, response, peer, sid, txid)


@pytest.fixture
def fake_board():
    boards = []
    def create(**kwargs):
        board = BoardSimulator(**kwargs)
        boards.append(board)
        return board
    yield create
    for board in boards:
        board.close()


def client_for(board, **kwargs):
    return StageDClient(board="127.0.0.1", local_ip="127.0.0.1", port=board.port, timeout=.5, **kwargs)


@pytest.mark.parametrize("start", [0, 5])
def test_v3_status_first_one_socket_nonzero_metadata_only_first_tx(fake_board, start):
    board = fake_board(start_round=start, duplicate=True)
    client = client_for(board)
    assert not board.requests
    assert client.connect()["protocol_version"] == 3
    assert board.requests == [b"STATUS"]
    client.initialize_utc(1700000000, 123)
    first = client.tx()
    assert first["comparison"]["exact"]
    assert len(first["packets"]) == (3 if start == 0 else 1)
    assert client.state == "WAITING_RX"
    with pytest.raises(StageDError):
        client.tx()
    returned = client.rx()
    assert returned["actual_iq"] == first["actual_iq"]
    assert returned["provenance"] == "FPGA RX S2MM"
    assert client.state == "READY"
    second = client.tx()
    assert len(second["packets"]) == 1
    client.rx()
    assert len(set(board.peers)) == 1
    assert all(not raw.startswith(MAGIC) for raw in board.requests)
    endpoint = client.sock.getsockname()
    client.disconnect()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as released:
        released.bind(endpoint)


def test_v3_pending_on_reconnect_is_honestly_unrecoverable_without_capture(fake_board):
    board = fake_board(start_round=2)
    board.pending, board.utc = 1, 1
    client = client_for(board)
    assert client.connect()["state"] == "RECOVERY_REQUIRED"
    with pytest.raises(StageDError, match="cached"):
        client.rx()
    assert board.requests == [b"STATUS"]
    client.disconnect()


def test_v3_ack_fail_never_becomes_success(fake_board):
    board = fake_board(ack_fail=True)
    client = client_for(board)
    client.connect()
    client.initialize_utc(1700000000)
    client.tx()
    with pytest.raises(StageDError, match="ACK FAIL"):
        client.rx()
    assert not client.connected and client.state == "FAULT"


def test_v3_custom_input_and_profile_are_rejected_before_tx(fake_board):
    board = fake_board()
    client = client_for(board)
    client.connect()
    client.initialize_utc(1700000000)
    with pytest.raises(StageDError, match="fixed"):
        client.tx([(0, 0)] * 256)
    with pytest.raises(StageDError, match="fixed"):
        client.configure(ProfileConfig(samples=4))
    assert b"TX" not in board.requests
    client.disconnect()


def test_timeout_does_not_retry_or_claim_ready(fake_board):
    board = fake_board(silence=True)
    client = client_for(board)
    with pytest.raises(TimeoutError):
        client.connect()
    assert board.requests == [b"STATUS"]
    assert not client.connected and client.state == "DISCONNECTED_INDETERMINATE"


def test_v4_binary_session_late_id_duplicates_actual_tx_rx(fake_board):
    board = fake_board(version=4, duplicate=True)
    client = client_for(board)
    assert client.connect()["protocol_version"] == 4
    assert [HEADER.unpack_from(raw)[2] for raw in board.requests[1:]] == [CAPS, OPEN]
    client.configure(ProfileConfig(samples=4))
    client.initialize_utc(1700000000)
    iq = [(1, -1), (32767, -32768), (-2, 3), (0, 0)]
    tx = client.tx(iq)
    assert tx["actual_iq"] == iq and tx["comparison"]["exact"]
    for packet in tx["packets"]:
        result = client.rx(packet["raw"])
        assert result["comparison"]["exact"]
        if packet["parsed"]["packet_type"] != "DATA":
            assert result["actual_iq"] == [] and result["comparison"]["not_requested"]
    assert client.state == "READY"
    ids = [HEADER.unpack_from(raw)[5] for raw in board.requests if raw.startswith(MAGIC)]
    assert ids == sorted(set(ids))
    assert len(set(board.peers)) == 1
    client.disconnect()


def test_v4_conflicting_duplicate_is_error(fake_board):
    board = fake_board(version=4, conflict=True)
    client = client_for(board)
    client.connect()
    client.configure(ProfileConfig(samples=4))
    client.initialize_utc(1700000000)
    with pytest.raises(StageDError, match="Conflicting duplicate"):
        client.tx([(1, -1)] * 4)
    assert client.state == "FAULT" and not client.connected


def test_stop_during_timeout_disconnects_indeterminate_without_retry(fake_board):
    board = fake_board()
    stopped = threading.Event()
    client = client_for(board, stop_event=stopped)
    client.connect()
    client.initialize_utc(1700000000)
    board.silence = True
    timer = threading.Timer(.03, stopped.set)
    timer.start()
    try:
        with pytest.raises(TimeoutError):
            client.tx()
    finally:
        timer.join()
    assert board.requests.count(b"TX") == 1
    assert client.state == "DISCONNECTED_INDETERMINATE" and not client.connected


def test_v4_reconnect_uses_new_session_identity(fake_board):
    board = fake_board(version=4)
    client = client_for(board)
    client.connect()
    first = client.session_id
    client.disconnect()
    client.connect()
    assert client.session_id != first
    assert client.transaction_id == 2  # CAPS then OPEN in the new identity.
    client.disconnect()


def test_tx_capture_uses_tx_sids_independent_of_rx_filters(fake_board):
    board = fake_board(version=4)
    client = client_for(board)
    client.connect()
    config = ProfileConfig(samples=4, data_sid=17, version_sid=23, rx_data_sid=99, rx_version_sid=100)
    client.configure(config)
    client.initialize_utc(1700000000)
    result = client.tx([(1, -1)] * 4)
    assert result["comparison"]["exact"]
    assert [item["parsed"]["stream_id"] for item in result["packets"]] == [23, 17, 17]
    with pytest.raises(ValueError, match="RX filter"):
        client.rx(result["packets"][-1]["raw"])
    client.disconnect()


def test_capability_limits_are_enforced_before_command_send(fake_board):
    board = fake_board(version=4)
    client = client_for(board)
    client.connect()
    previous = len(board.requests)
    client.capabilities["MAX_SAMPLES"] = 4
    with pytest.raises(StageDError, match="advertised"):
        client.configure(ProfileConfig(samples=8))
    client.capabilities["CONFIG"] = 0
    with pytest.raises(StageDError, match="capabilities"):
        client.configure(ProfileConfig(samples=4))
    assert len(board.requests) == previous
    client.capabilities["CONFIG"] = 1
    client.configure(ProfileConfig(samples=4))
    client.initialize_utc(1700000000)
    client.capabilities["CUSTOM_TX"] = 0
    with pytest.raises(StageDError, match="capabilities"):
        client.tx([(1, 2)] * 4)
    client.disconnect()


def test_config_mismatched_readback_is_fault(fake_board):
    board = fake_board(version=4)
    client = client_for(board)
    client.connect()
    original = board._v4
    def incorrect(raw, peer):
        header = HEADER.unpack_from(raw)
        if header[2] == CONFIG:
            board.frame(CONFIG | 0x80, "STATE=READY DATA_SID=999", peer, header[4], header[5])
        else:
            original(raw, peer)
    board._v4 = incorrect
    with pytest.raises(StageDError, match="readback"):
        client.configure(ProfileConfig(samples=4))
    assert not client.connected and client.state == "FAULT"


def test_status_body_must_confirm_same_session(fake_board):
    board = fake_board(version=4)
    client = client_for(board)
    client.connect()
    board.session += 1
    with pytest.raises(StageDError, match="session identity"):
        client.status()
    assert client.state == "FAULT" and not client.connected


def test_v4_done_may_arrive_before_streamed_payload(fake_board):
    board = fake_board(version=4, done_first=True)
    client = client_for(board)
    client.connect()
    client.configure(ProfileConfig(samples=4))
    client.initialize_utc(1700000000)
    tx = client.tx([(1, -1)] * 4)
    result = client.rx(tx["packets"][-1]["raw"])
    assert len(tx["packets"]) == 3 and result["comparison"]["exact"]
    client.disconnect()


def test_conflicting_duplicate_after_done_is_not_silently_ignored(fake_board):
    board = fake_board(version=4, late_conflict=True)
    client = client_for(board)
    client.connect()
    client.configure(ProfileConfig(samples=4))
    client.initialize_utc(1700000000)
    with pytest.raises(StageDError, match="Conflicting duplicate"):
        client.tx([(1, -1)] * 4)
    assert not client.connected


@pytest.mark.parametrize("fault", ["flags", "length", "error"])
def test_current_transaction_hostile_frame_cannot_become_ready(fake_board, fault):
    board = fake_board(version=4)
    client = client_for(board)
    client.connect()
    client.configure(ProfileConfig(samples=4))
    client.initialize_utc(1700000000)
    original = board._v4
    def hostile(raw, peer):
        header = HEADER.unpack_from(raw)
        if header[2] != TX:
            return original(raw, peer)
        body = b"STATE=READY TYPE=DATA SEQ=0 SAMPLES=4 PACKETS=1"
        opcode, flags, code = (0xFF if fault == "error" else DONE), int(fault == "flags"), int(fault == "error")
        length = len(body) + int(fault == "length")
        board.send(HEADER.pack(MAGIC, 4, opcode, flags, header[4], header[5], length, code) + body, peer)
    board._v4 = hostile
    with pytest.raises(StageDError):
        client.tx([(1, -1)] * 4)
    assert not client.connected and client.state == "FAULT"


def test_late_exact_done_is_ignored_for_next_transaction_with_bounded_history(fake_board):
    board = fake_board(version=4)
    client = client_for(board)
    client.connect()
    client.configure(ProfileConfig(samples=1))
    client.initialize_utc(1700000000)
    first = client.tx([(1, -1)])
    txid = first["transaction"]
    exact_done = client._completed_frames[txid][(DONE,)]
    peer = client.sock.getsockname()
    board.frame(DONE, exact_done, peer, client.session_id, txid)
    for _ in range(34):
        assert client.tx([(1, -1)])["comparison"]["exact"]
    assert len(client._completed_frames) == 32
    client.disconnect()
