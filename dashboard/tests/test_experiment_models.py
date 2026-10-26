"""Frozen-profile codec tests use synthetic packets and existing local captures."""

import json
from pathlib import Path
import struct

import pytest

from dashboard.app.experiment.models import ExperimentSession
from dashboard.app.experiment.profile import (
    ProfileConfig, build_packet, decode_config, decode_iq, encode_config, encode_iq, parse_packet,
)
from dashboard.app.models.events import Event


def replace_word(raw, index, value):
    data = bytearray(raw)
    struct.pack_into("!I", data, index * 4, value)
    return bytes(data)


def test_configuration_exact_network_layout_and_round_trip():
    config = ProfileConfig(data_sid=0x12345678, version_sid=0x87654321, samples=64,
                           sample_rate=0xFFFFFFFF, bandwidth=123, rf_hz=100_000_000_000,
                           rx_filter=1, rx_data_sid=987, rx_version_sid=654).validate()
    raw = encode_config(config)
    assert len(raw) == 40
    assert raw[:4] == bytes.fromhex("12345678")
    assert raw[20:28] == (100_000_000_000).to_bytes(8, "big")
    assert decode_config(raw) == config
    assert ProfileConfig.from_dict(config.to_dict()) == config
    with pytest.raises(ValueError):
        decode_config(raw[:-1])


@pytest.mark.parametrize("values", [
    {"samples": 0}, {"samples": 257}, {"samples": 1.0}, {"samples": True},
    {"sample_rate": 0}, {"sample_rate": 0x100000000}, {"bandwidth": 0},
    {"sample_rate": 10, "bandwidth": 11}, {"rf_hz": -1}, {"rf_hz": 100_000_000_001},
    {"rx_filter": -1}, {"rx_filter": 4}, {"data_sid": -1}, {"version_sid": 0x100000000},
    {"rx_data_sid": "1"}, {"rx_version_sid": False}, {"unknown": 1},
])
def test_bad_profile_values_are_never_silently_coerced(values):
    with pytest.raises(ValueError):
        ProfileConfig.from_dict(values)


@pytest.mark.parametrize("count", [1, 2, 64, 255, 256])
@pytest.mark.parametrize("sequence", [0, 15])
def test_arbitrary_data_samples_edges_and_full_profile_sizes(count, sequence):
    config = ProfileConfig(samples=count)
    pairs = [(-32768, 32767), (32767, -32768), (-1, 0), (0, -1)]
    pairs = [pairs[index % 4] for index in range(count)]
    raw = build_packet("DATA", config, pairs, sequence=sequence, picoseconds=999_999_999_999)
    packet = parse_packet(raw, config)
    assert packet["iq"] == pairs
    assert packet["samples"] == count
    assert packet["payload_bytes"] == (7 + count) * 4
    assert packet["sequence"] == sequence
    assert packet["picoseconds"] == 999_999_999_999
    assert len(packet["word_descriptions"]) == len(packet["words"])
    assert bytes.fromhex(packet["raw_hex"]) == raw


@pytest.mark.parametrize("kind,size", [("VERSION", 44), ("CONTEXT", 108)])
@pytest.mark.parametrize("changed", [True, False])
def test_metadata_roundtrip_and_fixed_fields(kind, size, changed):
    config = ProfileConfig(sample_rate=30_000_000, bandwidth=29_000_000, rf_hz=100_000_000_000)
    packet = parse_packet(build_packet(kind, config, sequence=15, changed=changed), config)
    assert packet["payload_bytes"] == size
    assert packet["fields"]["changed"] is changed
    assert packet["iq"] == [] and packet["samples"] == 0
    assert len(packet["word_descriptions"]) == len(packet["words"])
    if kind == "CONTEXT":
        assert packet["fields"]["rf_hz"] == 100_000_000_000
        assert packet["fields"]["bandwidth"] == 29_000_000
    else:
        assert packet["fields"]["build_year"] == 2026
        assert packet["fields"]["build_day"] == 252


@pytest.mark.parametrize("kind,index,value", [
    ("DATA", 0, 0x18600107), ("DATA", 2, 0), ("DATA", 3, 1),
    ("CONTEXT", 7, 0), ("CONTEXT", 8, 0), ("CONTEXT", 11, 1),
    ("CONTEXT", 12, 1), ("CONTEXT", 15, 1), ("CONTEXT", 18, 1),
    ("CONTEXT", 21, 1), ("CONTEXT", 24, 1), ("CONTEXT", 25, 0),
    ("CONTEXT", 26, 1), ("VERSION", 7, 3), ("VERSION", 8, 0),
    ("VERSION", 9, 0), ("VERSION", 10, (26 << 25) | (0 << 16) | 1024),
    ("VERSION", 10, (26 << 25) | (367 << 16) | 1024),
    ("VERSION", 10, (26 << 25) | (252 << 16) | 2048),
])
def test_frozen_header_oui_class_cif_dpf_reserved_and_version_fields(kind, index, value):
    raw = build_packet(kind, ProfileConfig(samples=1), [(1, -2)] if kind == "DATA" else None)
    with pytest.raises(ValueError):
        parse_packet(replace_word(raw, index, value))


@pytest.mark.parametrize("kind", ["DATA", "CONTEXT", "VERSION"])
def test_header_flags_truncation_timestamps_and_unknown_types_rejected(kind):
    raw = build_packet(kind, ProfileConfig(samples=2), [(1, 2), (3, 4)] if kind == "DATA" else None)
    header = int.from_bytes(raw[:4], "big")
    for mask in (1 << 27, 1 << 26, 1 << 25, 1 << 24, 1 << 23, 1 << 22, 1 << 21, 1 << 20):
        with pytest.raises(ValueError):
            parse_packet(replace_word(raw, 0, header ^ mask))
    with pytest.raises(ValueError):
        parse_packet(raw[:-1])
    with pytest.raises(ValueError):
        parse_packet(raw + b"\0\0\0\0")
    bad = replace_word(raw, 5, 1_000_000_000_000 >> 32)
    bad = replace_word(bad, 6, 1_000_000_000_000 & 0xFFFFFFFF)
    with pytest.raises(ValueError, match="timestamp"):
        parse_packet(bad)
    with pytest.raises(ValueError):
        parse_packet(replace_word(raw, 0, (header & 0x0FFFFFFF) | (15 << 28)))


def test_context_range_fractional_hz_and_independent_rx_frequencies():
    raw = build_packet("CONTEXT", ProfileConfig())
    with pytest.raises(ValueError, match="fractional"):
        parse_packet(replace_word(raw, 10, int.from_bytes(raw[40:44], "big") | 1))
    with pytest.raises(ValueError, match="frequency values"):
        parse_packet(replace_word(replace_word(raw, 9, 0), 10, 0))
    packet = parse_packet(raw, ProfileConfig(sample_rate=30_000_000))
    assert packet["fields"]["sample_rate"] == 20_000_000


def test_rx_filters_are_independent_and_not_tx_sid_assumptions():
    tx = ProfileConfig(data_sid=0xFFFFFFFF, version_sid=17, samples=1)
    for kind in ("DATA", "CONTEXT", "VERSION"):
        raw = build_packet(kind, tx, [(4, -5)] if kind == "DATA" else None)
        with pytest.raises(ValueError, match="Stream ID"):
            parse_packet(raw, ProfileConfig())
        assert parse_packet(raw, ProfileConfig(rx_filter=0))["stream_id"] == (17 if kind == "VERSION" else 0xFFFFFFFF)
    version = build_packet("VERSION", tx)
    assert parse_packet(version, ProfileConfig(rx_filter=1))["stream_id"] == 17
    data = build_packet("DATA", tx, [(4, -5)])
    assert parse_packet(data, ProfileConfig(rx_filter=2))["samples"] == 1
    assert parse_packet(data, ProfileConfig(rx_filter=0))["fields"]["sample_count_matches_profile"] is False


@pytest.mark.parametrize("kwargs", [{"sequence": 16}, {"sequence": -1}, {"sequence": True},
    {"seconds": -1}, {"seconds": 0x100000000}, {"picoseconds": 1_000_000_000_000}, {"changed": 1}])
def test_builders_reject_invalid_control_fields(kwargs):
    with pytest.raises(ValueError):
        build_packet("DATA", ProfileConfig(samples=1), [(0, 0)], **kwargs)


def test_data_requires_explicit_correct_sample_count_and_strict_i16():
    config = ProfileConfig(samples=1)
    for pairs in (None, [], [(0, 0), (1, 1)], [(32768, 0)], [(-32769, 0)], [(1.0, 0)], [(True, 0)]):
        with pytest.raises(ValueError):
            build_packet("DATA", config, pairs)
    with pytest.raises(ValueError):
        build_packet("CONTEXT", config, [(0, 0)])
    pairs = [(-32768, 32767), (-1, 0)]
    assert encode_iq(pairs) == bytes.fromhex("80007FFFFFFF0000")
    assert decode_iq(encode_iq(pairs, "little"), "little") == pairs
    for bad in (b"\0", b"\0\0", b"\0\0\0"):
        with pytest.raises(ValueError):
            decode_iq(bad)


def test_packet_sequences_wrap_15_to_0_without_coupling_metadata_streams():
    config = ProfileConfig(samples=1)
    packets = [build_packet("VERSION", config, sequence=9),
               build_packet("CONTEXT", config, sequence=4),
               build_packet("DATA", config, [(1, -1)], sequence=15),
               build_packet("DATA", config, [(2, -2)], sequence=0)]
    parsed = [parse_packet(packet, config) for packet in packets]
    assert [(packet["packet_type"], packet["sequence"]) for packet in parsed] == [
        ("VERSION", 9), ("CONTEXT", 4), ("DATA", 15), ("DATA", 0)]


def test_existing_stage_d_archived_packets_remain_compatible():
    root = Path(__file__).resolve().parents[2]
    directory = root / "scripts/verify/tools/captures/stage_e1"
    for name in ("version", "context", "data"):
        path = directory / f"round00_fpga_tx_{name}.difi"
        if not path.exists():
            pytest.skip("Optional archived Stage D capture is absent")
        packet = parse_packet(path.read_bytes())
        assert packet["packet_type"] == name.upper()
        assert packet["samples"] == (256 if name == "data" else 0)


def test_session_evidence_lifecycle_and_bytes_are_portable_json():
    session = ExperimentSession(source="REPLAY")
    session.apply_event(Event("CONNECTED", "REPLAY", {"capabilities": {"config": False}}))
    assert session.state == "CONNECTED" and session.capabilities["config"] is False
    session.apply_event(Event("TRANSACTION_START", "REPLAY"))
    assert session.started_at and session.state == "RUNNING"
    with pytest.raises(RuntimeError):
        session.transition("RUNNING")
    session.apply_event(Event("IQ_CAPTURE", "REPLAY", {"raw": b"\xff\0", "fixture": True}))
    session.apply_event(Event("TRANSACTION_COMPLETE", "REPLAY", {"status": "PASS", "exact": True}))
    assert session.state == "READY"
    value = json.loads(json.dumps(session.to_dict()))
    assert value["captures"][0]["raw"] == "ff00"
    assert value["transactions"][0]["source"] == "REPLAY"
    assert value["classification"] == "REPLAY / OFFLINE"
    session.apply_event(Event("SESSION_COMPLETE", "REPLAY"))
    assert session.state == "READY"  # A summary cannot fabricate overall verification.
    session.apply_event(Event("SESSION_ERROR", "REPLAY", {"message": "timeout"}))
    assert session.state == "FAILED" and session.errors == ["timeout"]
    assert session.ended_at


def test_session_stop_disconnect_and_detached_snapshots_preserve_sources():
    session = ExperimentSession(source="LIVE", parameters={"profile": {"samples": 2}})
    with pytest.raises(ValueError):
        session.apply_event(Event("CONNECTED", "REPLAY"))
    event = Event("CONNECTED", "LIVE", {"capabilities": {"config": True}})
    session.apply_event(event)
    event.data["capabilities"]["config"] = False
    assert session.events[0].data["capabilities"]["config"] is True
    session.apply_event(Event("TRANSACTION_START", "LIVE"))
    session.apply_event(Event("STOP_REQUESTED", "LIVE"))
    assert session.state == "STOPPING"
    session.apply_event(Event("SESSION_STOPPED", "LIVE"))
    assert session.state == "STOPPED" and session.ended_at
    session.apply_event(Event("CONNECTION_CLOSED", "LIVE"))
    assert session.state == "DISCONNECTED"
    value = session.to_dict()
    value["parameters"]["profile"]["samples"] = 200
    assert session.parameters["profile"]["samples"] == 2


@pytest.mark.parametrize("evidence", [{"source": "REPLAY"}, {"source": "REPLAY/fixture"},
    {"fixture": True}, {"synthetic": True}, {"nested": {"simulated": True}}])
def test_session_cannot_relabel_fixtures_as_live(evidence):
    session = ExperimentSession(source="LIVE")
    with pytest.raises(ValueError):
        session.record_capture(evidence)
    assert not session.captures
    with pytest.raises(ValueError):
        session.apply_event(Event("IQ_CAPTURE", "LIVE", evidence))
    assert not session.events
    session.captures.append(evidence)
    with pytest.raises(ValueError):
        session.to_dict()
