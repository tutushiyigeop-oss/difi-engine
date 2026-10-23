"""Synthetic binary capture fixtures; no hardware or network access."""

import struct

import pytest

from dashboard.app.services.capture_decoder import decode_capture, decode_iq


def synthetic_packets():
    version = [0x5960000B, 2, 0x006A621E, 0x00010004, 1700000000, 0, 0,
               0x80000002, 12, 4, 0]
    context = [0] * 27
    context[:8] = [0x4960001B, 1, 0x006A621E, 1, 1700000000, 0, 0, 0xFBB98000]
    context[25] = 0xA00003CF
    data = [0x18600107, 1, 0x006A621E, 0, 1700000000, 0, 0]
    data.extend([0x0001FFFF, 0x7FFF8000, 0xFFFE0003, 0])
    for index in range(4, 256):
        data.append(((0x1000 + index) << 16) | (0xA000 + 3 * index))
    return [struct.pack(f"!{len(words)}I", *words) for words in (version, context, data)]


def write_capture(path, packets):
    path.write_bytes(b"".join(struct.pack("!I", len(packet)) + packet for packet in packets))
    return path


def test_network_prefix_metadata_and_signed_i16q16(tmp_path):
    packets = synthetic_packets()
    records = decode_capture(write_capture(tmp_path / "synthetic.bin", packets))
    assert [record["packet_type"] for record in records] == ["VERSION", "CONTEXT", "DATA"]
    assert [record["payload_bytes"] for record in records] == [44, 108, 1052]
    assert records[0]["i"] == records[1]["q"] == []
    assert records[2]["i"][:4] == [1, 32767, -2, 0]
    assert records[2]["q"][:4] == [-1, -32768, 3, 0]
    assert len(records[2]["i"]) == 256
    assert records[2]["verified"] is True


def test_complete_partial_capture_is_useful_after_timeout(tmp_path):
    records = decode_capture(write_capture(tmp_path / "partial.bin", synthetic_packets()[:1]))
    assert len(records) == 1
    assert records[0]["packet_type"] == "VERSION"


def test_limited_snapshot_does_not_read_unconfirmed_trailing_packet(tmp_path):
    path = write_capture(tmp_path / "in_progress.bin", synthetic_packets())
    path.write_bytes(path.read_bytes() + b"\x00\x00")
    records = decode_capture(path, limit=3)
    assert len(records) == 3 and records[-1]["iq_samples"] == 256
    with pytest.raises(ValueError, match="length prefix"):
        decode_capture(path)
    assert decode_capture(path, limit=0) == []
    with pytest.raises(ValueError, match="negative"):
        decode_capture(path, limit=-1)


@pytest.mark.parametrize("contents", [b"\x00", struct.pack("!I", 44) + b"\0" * 40,
                                         struct.pack("!I", 0), struct.pack("<I", 44)])
def test_truncated_or_wrong_endian_prefix_rejected(tmp_path, contents):
    path = tmp_path / "invalid.bin"
    path.write_bytes(contents)
    with pytest.raises(ValueError):
        decode_capture(path)


def test_uses_original_checker_before_showing_iq(tmp_path):
    packets = synthetic_packets()
    corrupt = bytearray(packets[-1])
    corrupt[28] ^= 1
    packets[-1] = bytes(corrupt)
    with pytest.raises(ValueError, match="sample=0"):
        decode_capture(write_capture(tmp_path / "bad_iq.bin", packets))
    # Valid data at the wrong capture index is not accepted as a complete B5 flow.
    with pytest.raises(ValueError, match="type 1 expected 5"):
        decode_capture(write_capture(tmp_path / "missing_metadata.bin", packets[2:]))


def test_decode_iq_does_not_accept_wrong_shape():
    with pytest.raises(ValueError):
        decode_iq(b"\0" * 1024)
