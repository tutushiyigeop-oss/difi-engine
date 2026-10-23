"""All log lines below are synthetic fixtures, not hardware evidence."""

import pytest

from dashboard.app.services.output_parser import OutputParser


@pytest.mark.parametrize("line,kind,sequence,size,samples", [
    ("[PASS] #00 type=5 seq= 0 words= 11 bytes=  44", "VERSION", 0, 44, 0),
    ("[PASS] #01 type=4 seq= 0 words= 27 bytes= 108", "CONTEXT", 0, 108, 0),
    ("[PASS] #17 type=1 seq=15 words=263 bytes=1052", "DATA", 15, 1052, 256),
    ("[PASS] #18 type=1 seq= 0 words=263 bytes=1052", "DATA", 0, 1052, 256),
])
def test_validated_packet_fields(line, kind, sequence, size, samples):
    events = OutputParser("B5", "REPLAY").feed(line)
    packet = next(event for event in events if event.kind == "PACKET_PASS")
    assert packet.source == "REPLAY"
    assert packet.data["packet_type"] == kind
    assert packet.data["sequence"] == sequence
    assert packet.data["payload_bytes"] == size
    assert packet.data["iq_samples"] == samples
    assert packet.data["verified"] is True


@pytest.mark.parametrize("line", [
    "[FAIL] packet #2: header 0x0 != 0x18600107",
    "[FAIL] timeout waiting packet #5; received 5/22. Check board UART, PC IP/firewall.",
    "[FAIL] expected [PASS] #02 type=1 seq= 0 words=263 bytes=1052",
    "[PASS] #02 type=1 seq= 0 words=263 bytes=1024",
    "[PASS] #02 type=4 seq= 0 words= 27 bytes=108",
    "[PASS] #02 type=1 seq=16 words=263 bytes=1052",
    "[PASS] #02 type=1 seq= 1 words=263 bytes=1052",
    "[PASS] #22 type=1 seq= 4 words=263 bytes=1052",
])
def test_error_or_malformed_pass_cannot_create_success(line):
    events = OutputParser("B5").feed(line)
    assert events
    assert not any(event.kind == "PACKET_PASS" for event in events)


def test_summary_only_and_pc_listener_is_not_board_ready():
    parser = OutputParser("B5")
    assert parser.feed("[INFO] UDP listening on 192.168.1.20:4991")[0].kind == "SESSION_START"
    events = parser.feed("[PASS] DIFI UDP full chain: 1 Version + 1 Context + 20 Data, 5120 IQ correct")
    assert len(events) == 1
    assert events[0].kind == "SESSION_COMPLETE"
    assert events[0].data["summary"] is True
    assert parser.feed("[INFO] sending START to 192.168.1.10:4991") == []


def test_known_iq_mismatch_preserves_partial_failure_evidence():
    event = OutputParser("B5").feed("[FAIL] Data round=3 sample=4: 0x00000000 != 0x1604a03f")[0]
    assert event.kind == "PACKET_FAIL"
    assert event.data["mismatches"] == 1
    assert event.data["mismatches_are_minimum"] is True
