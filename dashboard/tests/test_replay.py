"""Synthetic replay tests: no board traffic, no archived hardware claims."""
import json
import socket
from pathlib import Path

import pytest
from PySide6.QtCore import QEventLoop, QTimer

from dashboard.app.models.session import Session
from dashboard.app.models.events import Event
from dashboard.app.services.capture_decoder import decode_capture
from dashboard.app.services.replay_service import ReplayService, fixture_lines
from dashboard.app.services.result_exporter import export_session
from dashboard.app.config import DemoConfig


def spin_until(qapp, condition, seconds=5):
    if condition():
        return
    loop = QEventLoop()
    check = QTimer()
    check.setInterval(1)
    check.timeout.connect(lambda: loop.quit() if condition() else None)
    deadline = QTimer()
    deadline.setSingleShot(True)
    deadline.timeout.connect(loop.quit)
    check.start()
    deadline.start(int(seconds * 1000))
    loop.exec()
    check.stop()
    deadline.stop()
    assert condition(), "Qt operation did not finish within the test deadline"


@pytest.mark.parametrize("mode", ["B5", "B6"])
def test_replay_is_network_free_and_uses_confirmed_fixture_events(qapp, monkeypatch, tmp_path, mode):
    def forbidden(*args, **kwargs):
        raise AssertionError("Replay must never create sockets or resolve board names")
    monkeypatch.setattr(socket, "socket", forbidden)
    monkeypatch.setattr(socket, "gethostbyname", forbidden)
    replay = ReplayService(interval_ms=1)
    session = Session(mode, "REPLAY", {})
    session.start()
    logs, finishes = [], []
    replay.event.connect(session.apply)
    replay.log.connect(lambda level, source, message: logs.append({"level": level, "source": source, "message": message}))
    replay.finished.connect(lambda code, stopped: (session.finish(code, stopped), finishes.append((code, stopped))))
    assert replay.start(mode, {}, tmp_path)
    assert session.total_packets == 0
    assert not replay.start(mode, {}, tmp_path)
    spin_until(qapp, lambda: not replay.running)
    assert finishes == [(0, False)]
    assert session.state == "COMPLETED"
    assert session.counts == {"VERSION": 1, "CONTEXT": 1, "DATA": 20}
    assert session.verified_iq == 5120
    assert session.payload_bytes == 21192
    assert all(event.source == "REPLAY" for event in session.events)
    assert all("REPLAY" in entry["source"] for entry in logs)
    assert any("SIMULATED TEST FIXTURE" in entry["message"] for entry in logs)
    if mode == "B5":
        assert replay.capture_path is not None
        records = decode_capture(replay.capture_path)
        assert len(records) == 22
        assert records[2]["i"][:4] == [1, 32767, -2, 0]
        assert records[2]["q"][:4] == [-1, -32768, 3, 0]
    else:
        assert replay.capture_path is None
        assert session.board_status["NEXT_ROUND"] == 14
        assert session.board_status["NEXT_VERSION"] == 3
        assert session.board_status["NEXT_CONTEXT"] == 7
        assert any(item["wrap"] for item in session.sequence_history["DATA"])
        assert not session.sequence_issues


def test_replay_selected_types_and_rounds_are_actual_counts(qapp, tmp_path):
    replay = ReplayService(interval_ms=1)
    parameters = {"types": "data", "rounds": 3}
    session = Session("B6", "REPLAY", parameters)
    session.start()
    replay.event.connect(session.apply)
    replay.finished.connect(session.finish)
    assert replay.start("B6", parameters, tmp_path)
    spin_until(qapp, lambda: not replay.running)
    assert session.state == "COMPLETED"
    assert session.counts == {"VERSION": 0, "CONTEXT": 0, "DATA": 3}
    assert session.verified_iq == 768
    assert [packet["sequence"] for packet in session.packets] == [14, 15, 0]


def test_stop_and_restart_do_not_retain_previous_replay_events(qapp, tmp_path):
    replay = ReplayService(interval_ms=1)
    finishes, packets = [], []
    replay.event.connect(lambda event: packets.append(event) if event.kind == "PACKET_PASS" else None)
    replay.finished.connect(lambda code, stopped: finishes.append((code, stopped)))
    assert replay.start("B6", {}, tmp_path)
    spin_until(qapp, lambda: len(packets) >= 2)
    replay.stop()
    replay.stop()
    count_at_stop = len(packets)
    spin_until(qapp, lambda: not replay.running)
    assert len(packets) == count_at_stop
    assert finishes == [(0, True)]
    assert replay.start("B6", {"types": "version"}, tmp_path)
    spin_until(qapp, lambda: not replay.running)
    assert finishes == [(0, True), (0, False)]
    assert len(packets) == count_at_stop + 1


def test_replay_exports_keep_source_and_raw_messages(qapp, tmp_path):
    replay = ReplayService(interval_ms=1)
    session = Session("B6", "REPLAY", {"types": "version"})
    session.start()
    logs = []
    replay.event.connect(session.apply)
    replay.finished.connect(session.finish)
    replay.log.connect(lambda level, source, message: logs.append({"timestamp": "test-time", "level": level, "source": source, "message": message}))
    assert replay.start("B6", {"types": "version"}, tmp_path)
    spin_until(qapp, lambda: not replay.running)
    paths = export_session(session, logs, tmp_path / "exports")
    data = json.loads(paths["json"].read_text(encoding="utf-8"))
    assert data["session"]["source"] == "REPLAY"
    assert data["classification"].startswith("REPLAY PASS")
    assert "not a hardware test" in data["classification"]
    assert data["logs"] == logs
    assert "Golden Reference" in data["waveform_source"]
    assert "GPIO error counter / changed flag | Not Observable" in paths["md"].read_text(encoding="utf-8")
    for entry in logs:
        assert entry["message"] in paths["txt"].read_text(encoding="utf-8")
    assert not list((tmp_path / "exports").glob("*.tmp"))


def test_fixture_text_is_explicitly_available_for_parser_regression():
    assert "NEXT_ROUND=14" in fixture_lines("B6", DemoConfig.for_mode("B6"))[0]
    assert len([line for line in fixture_lines("B5", DemoConfig()) if line.startswith("[PASS] #")]) == 22


def test_export_frozen_snapshot_preserves_observed_minimum_mismatch(tmp_path):
    session = Session("B5", "LIVE", {})
    session.start()
    session.apply(Event("PACKET_FAIL", "LIVE", {"packet_type": "DATA", "message": "first IQ mismatch",
                                               "mismatches": 1, "mismatches_are_minimum": True}))
    session.finish(1)
    paths = export_session(session.to_dict(), [], tmp_path)
    assert "≥1 (observed minimum)" in paths["md"].read_text(encoding="utf-8")
    data = json.loads(paths["json"].read_text(encoding="utf-8"))
    assert data["session"]["mismatches_are_minimum"] is True
    assert data["classification"] == "LIVE FAILED"


@pytest.mark.parametrize("mode,expected", [
    ("B5", "No samples available"), ("B6", "No Golden Reference displayed"),
])
def test_export_without_data_does_not_claim_waveform_evidence(tmp_path, mode, expected):
    session = Session(mode, "LIVE", {})
    paths = export_session(session, [], tmp_path)
    data = json.loads(paths["json"].read_text(encoding="utf-8"))
    assert data["waveform_source"].startswith(expected)
    assert expected in paths["md"].read_text(encoding="utf-8")


@pytest.mark.parametrize("mode", ["B5", "B6"])
def test_marked_fixture_files_match_generated_packet_evidence(mode):
    fixture = Path(__file__).parent / "fixtures" / f"{mode.lower()}_sample.log"
    text = fixture.read_text(encoding="utf-8")
    assert text.startswith("# SIMULATED TEST FIXTURE; NOT A HARDWARE RUN")
    generated_packets = [line for line in fixture_lines(mode, DemoConfig.for_mode(mode)) if line.startswith("[PASS]")]
    stored_packets = [line for line in text.splitlines() if line.startswith("[PASS]")]
    assert generated_packets == stored_packets
