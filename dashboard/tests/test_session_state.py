"""Session acceptance and sequence tests use explicitly synthetic events."""

import json

import pytest

from dashboard.app.models.events import Event
from dashboard.app.models.session import Session
from dashboard.app.services.output_parser import OutputParser


def apply_lines(session, lines):
    parser = OutputParser(session.mode, session.source)
    for line in lines:
        for event in parser.feed(line):
            session.apply(event)


def full_b6_lines(start=14):
    yield f"[BOARD] READY NEXT_ROUND={start} NEXT_VERSION=3 NEXT_CONTEXT=7"
    yield "[PASS] VERSION bytes=  44 ACK PASS TYPE=VERSION SEQ=3 META=1"
    yield "[PASS] CONTEXT bytes= 108 ACK PASS TYPE=CONTEXT SEQ=7 META=1"
    for round_id in range(start, start + 20):
        yield f"[PASS] DATA    bytes=1052 ACK PASS ROUND={round_id} SEQ={round_id % 16} IQ=256"
    yield "[PASS] Selected B6 packet types validated by the board"


def test_nonzero_counts_wrap_and_exact_20_data_5120_iq():
    session = Session(mode="B6")
    session.start()
    assert session.state == "PREPARING"
    assert session.total_packets == session.verified_iq == 0
    assert session.mismatches is None
    apply_lines(session, full_b6_lines())
    assert session.state == "RUNNING"  # Summary is not a process exit.
    assert session.counts == {"VERSION": 1, "CONTEXT": 1, "DATA": 20}
    assert session.payload_bytes == 21192
    assert session.verified_iq == session.expected_iq == 5120
    assert session.mismatches == 0
    assert not session.sequence_issues
    history = session.sequence_history["DATA"]
    assert [item["sequence"] for item in history[:4]] == [14, 15, 0, 1]
    assert history[2]["wrap"] is True
    assert session.sequence_history["VERSION"][0]["sequence"] == 3
    session.finish(0)
    assert session.state == "COMPLETED"
    assert json.loads(json.dumps(session.to_dict()))["source"] == "REPLAY"


@pytest.mark.parametrize("exit_code", [1, 2, -1])
def test_good_packet_summary_never_overrides_nonzero_exit(exit_code):
    session = Session(mode="B6")
    session.start()
    apply_lines(session, full_b6_lines())
    session.finish(exit_code)
    assert session.state == "FAILED"


def test_zero_exit_still_requires_summary_and_real_packet_counts():
    session = Session(mode="B6")
    session.start()
    apply_lines(session, ["[PASS] Selected B6 packet types validated by the board"])
    session.finish(0)
    assert session.state == "FAILED"
    assert session.total_packets == 0
    assert session.mismatches is None
    without_summary = Session(mode="B6")
    apply_lines(without_summary, list(full_b6_lines())[:-1])
    without_summary.finish(0)
    assert without_summary.state == "FAILED"


def test_packet_identity_deduplicates_but_repeated_sequence_is_reported():
    session = Session(mode="B6", parameters={"types": "data", "rounds": 2})
    data = {"packet_id": "a", "packet_type": "DATA", "sequence": 15,
            "payload_bytes": 1052, "iq_samples": 256, "verified": True}
    event = Event("PACKET_PASS", "REPLAY", data)
    session.apply(event)
    session.apply(event)
    assert session.counts["DATA"] == 1
    assert len(session.sequence_history["DATA"]) == 1
    session.apply(Event("PACKET_PASS", "REPLAY", {**data, "packet_id": "b"}))
    assert session.counts["DATA"] == 2
    assert "Repeated sequence 15" in session.sequence_issues[0]["issue"]
    session.apply(Event("SESSION_COMPLETE", "REPLAY", {"summary": True}))
    session.finish(0)
    assert session.state == "FAILED"


def test_metadata_only_expectations_and_observability():
    session = Session(mode="B6", parameters={"types": ["version"], "rounds": 20})
    assert session.expected_counts == {"VERSION": 1, "CONTEXT": 0, "DATA": 0}
    assert session.expected_packets == 1 and session.expected_iq == 0
    apply_lines(session, [
        "[BOARD] READY NEXT_ROUND=40 NEXT_VERSION=9 NEXT_CONTEXT=7",
        "[PASS] VERSION bytes=  44 ACK PASS TYPE=VERSION SEQ=9 META=1",
        "[PASS] Selected B6 packet types validated by the board"])
    session.finish(0)
    assert session.state == "COMPLETED"
    assert session.mismatches is None
    assert "GPIO_ERRORS" not in session.board_status


def test_stop_duplicate_start_and_fresh_session_reset():
    session = Session()
    session.start()
    with pytest.raises(RuntimeError):
        session.start()
    session.finish(-1, stopped=True)
    assert session.state == "STOPPED"
    session.apply(Event("SESSION_COMPLETE", "REPLAY", {"summary": True}))
    assert not session.summary_seen
    fresh = Session()
    assert fresh.state == "IDLE" and fresh.total_packets == 0
    assert fresh.mismatches is None and not fresh.events
    assert fresh.id != session.id


def test_live_replay_cannot_mix_and_export_is_detached():
    session = Session()
    with pytest.raises(ValueError):
        session.apply(Event("BOARD_READY", "LIVE", {"NEXT_ROUND": 0}))
    snapshot = session.to_dict()
    snapshot["counts"]["DATA"] = 100
    assert session.counts["DATA"] == 0


def test_packet_fail_and_unobservable_iq_never_fabricate_zero_mismatches():
    session = Session(mode="B6", parameters={"types": "version"})
    apply_lines(session, ["[FAIL] version: ACK FAIL META=0 (expected ACK PASS TYPE=VERSION SEQ=3 META=1)"])
    assert session.mismatches is None
    assert session.total_packets == 0
    assert len(session.packets) == 1 and session.packets[0]["status"] == "FAIL"
    assert session.packets[0]["verified"] is False
    session.finish(1)
    assert session.state == "FAILED"


def test_first_iq_failure_is_a_minimum_not_a_fabricated_full_mismatch_total():
    session = Session(mode="B5")
    apply_lines(session, ["[FAIL] Data round=3 sample=4: 0x00000000 != 0x1604a03f"])
    assert session.mismatches == 1
    assert session.mismatches_are_minimum is True
    assert session.verified_iq == 0
    assert session.to_dict()["mismatches_are_minimum"] is True


def test_b6_iq_mismatch_ack_overrides_prior_zero_mismatch_count():
    session = Session(mode="B6", parameters={"types": "data", "rounds": 2})
    apply_lines(session, [
        "[BOARD] READY NEXT_ROUND=14 NEXT_VERSION=3 NEXT_CONTEXT=7",
        "[PASS] DATA    bytes=1052 ACK PASS ROUND=14 SEQ=14 IQ=256",
        "[FAIL] data: ACK FAIL REASON=IQ_MISMATCH (expected ACK PASS ROUND=15 SEQ=15 IQ=256)"])
    assert session.verified_iq == 256
    assert session.mismatches == 1
    assert session.mismatches_are_minimum is True
    assert session.counts["DATA"] == 1
    session.finish(1)
    assert session.state == "FAILED"


def test_b5_full_flow_and_per_type_sequence():
    session = Session(mode="B5")
    lines = ["[PASS] #00 type=5 seq= 0 words= 11 bytes=  44",
             "[PASS] #01 type=4 seq= 0 words= 27 bytes= 108"]
    lines.extend(f"[PASS] #{index + 2:02d} type=1 seq={index % 16:2d} words=263 bytes=1052"
                 for index in range(20))
    lines.append("[PASS] DIFI UDP full chain: 1 Version + 1 Context + 20 Data, 5120 IQ correct")
    apply_lines(session, lines)
    session.finish(0)
    assert session.state == "COMPLETED"
    assert session.total_packets == 22
    assert not session.sequence_issues
