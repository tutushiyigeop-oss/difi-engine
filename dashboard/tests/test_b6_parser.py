"""Synthetic stdout examples follow difi_b6_three_types.py exactly."""

import pytest

from dashboard.app.services.output_parser import OutputParser


def test_status_preserves_nonzero_independent_board_counters():
    parser = OutputParser("B6", "REPLAY")
    events = parser.feed("[BOARD] READY NEXT_ROUND=94 NEXT_VERSION=3 NEXT_CONTEXT=7")
    assert events[0].kind == "BOARD_READY"
    assert events[0].data["NEXT_ROUND"] == 94
    assert events[0].data["NEXT_VERSION"] == 3
    assert events[0].data["NEXT_CONTEXT"] == 7
    version = parser.feed("[PASS] VERSION bytes=  44 ACK PASS TYPE=VERSION SEQ=3 META=1")[0]
    context = parser.feed("[PASS] CONTEXT bytes= 108 ACK PASS TYPE=CONTEXT SEQ=7 META=1")[0]
    data = parser.feed("[PASS] DATA    bytes=1052 ACK PASS ROUND=94 SEQ=14 IQ=256")[0]
    assert version.data["packet_id"] == "b6:version:3"
    assert context.data["packet_id"] == "b6:context:7"
    assert data.data["round"] == 94
    assert data.data["sequence"] == 14
    assert data.data["iq_samples"] == 256


@pytest.mark.parametrize("line", [
    "[FAIL] data: ACK FAIL ROUND=14 ERROR=3 (expected ACK PASS ROUND=14 SEQ=14 IQ=256)",
    "[FAIL] version: ACK PASS TYPE=VERSION SEQ=4 META=1 (expected ACK PASS TYPE=VERSION SEQ=3 META=1)",
    "[FAIL] context: ACK FAIL META=0 (expected ACK PASS TYPE=CONTEXT SEQ=7 META=1)",
    "[PASS] DATA    bytes=1024 ACK PASS ROUND=14 SEQ=14 IQ=256",
    "[PASS] DATA    bytes=1052 ACK PASS ROUND=14 SEQ=0 IQ=256",
    "[PASS] VERSION bytes=  44 ACK PASS TYPE=CONTEXT SEQ=3 META=1",
    "[PASS] VERSION bytes= 108 ACK PASS TYPE=VERSION SEQ=3 META=1",
    "[PASS] DATA    bytes=1052 ACK PASS ROUND=14 SEQ=14 IQ=255",
])
def test_bad_ack_or_embedded_expected_ack_never_counts(line):
    events = OutputParser("B6").feed(line)
    assert events
    assert not any(event.kind in {"PACKET_PASS", "IQ_VERIFIED", "METADATA_PASS"} for event in events)


def test_expected_ack_sequence_not_reported_as_received_failure_sequence():
    event = OutputParser("B6").feed(
        "[FAIL] data: ACK FAIL ROUND=14 ERROR=3 (expected ACK PASS ROUND=14 SEQ=14 IQ=256)")[0]
    assert event.kind == "PACKET_FAIL"
    assert "sequence" not in event.data
    missing_round = OutputParser("B6").feed(
        "[FAIL] data: UNKNOWN COMMAND (expected ACK PASS ROUND=14 SEQ=14 IQ=256)")[0]
    assert "round" not in missing_round.data


def test_actual_board_iq_mismatch_ack_is_known_minimum_failure():
    event = OutputParser("B6").feed(
        "[FAIL] data: ACK FAIL REASON=IQ_MISMATCH (expected ACK PASS ROUND=14 SEQ=14 IQ=256)")[0]
    assert event.kind == "PACKET_FAIL"
    assert event.data["packet_type"] == "DATA"
    assert event.data["mismatches"] == 1
    assert event.data["mismatches_are_minimum"] is True
    assert "sequence" not in event.data and "round" not in event.data


@pytest.mark.parametrize("line", [
    "[BOARD] READY NEXT_ROUND=94", "[BOARD] WRONG_ELF",
    "[BOARD] READY NEXT_ROUND=-1 NEXT_VERSION=0 NEXT_CONTEXT=0",
    "[BOARD] READY NEXT_ROUND=1 NEXT_VERSION=0 NEXT_CONTEXT=0 NEXT_ROUND=2",
])
def test_malformed_or_wrong_elf_status_is_error(line):
    assert OutputParser("B6").feed(line)[0].kind == "SESSION_ERROR"


def test_dry_run_and_standalone_ack_are_not_hardware_success():
    parser = OutputParser("B6")
    assert parser.feed("[DRY] DATA bytes=1052 word0=0x18600107") == []
    assert parser.feed("ACK PASS ROUND=0 SEQ=0 IQ=256") == []
    summary = parser.feed("[PASS] Selected B6 packet types validated by the board")
    assert len(summary) == 1 and summary[0].data["summary"] is True
