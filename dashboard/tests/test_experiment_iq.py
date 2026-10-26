"""Deterministic PC reference generation and strict dataset file tests."""

import math

import pytest

from dashboard.app.experiment.iq import (
    KINDS, compare_iq, export_iq_bin, export_iq_csv, generate_iq, import_iq_bin, import_iq_csv,
)


@pytest.mark.parametrize("count", [1, 2, 64, 255, 256])
@pytest.mark.parametrize("kind", KINDS)
def test_each_generator_returns_signed_deterministic_pc_samples(kind, count):
    samples = generate_iq(kind, count, seed=87, chirp_end=4_000_000, constant_i=-32768, constant_q=32767)
    assert len(samples) == count
    assert samples == generate_iq(kind, count, seed=87, chirp_end=4_000_000, constant_i=-32768, constant_q=32767)
    assert all(-32768 <= value <= 32767 and isinstance(value, int) for pair in samples for value in pair)


def test_complex_and_real_phase_conventions_and_prbs_seed():
    samples = generate_iq("complex_sine", 4, amplitude=100, frequency=1, sample_rate=4)
    assert samples == [(100, 0), (0, 100), (-100, 0), (0, -100)]
    assert generate_iq("real_sine", 4, amplitude=100, frequency=1, sample_rate=4) == [(0, 0), (100, 0), (0, 0), (-100, 0)]
    assert generate_iq("complex_sine", 1, amplitude=100, phase=math.pi / 2) == [(0, 100)]
    assert generate_iq("constant", 2, constant_i=-32768, constant_q=32767) == [(-32768, 32767)] * 2
    assert generate_iq("prbs", seed=1) != generate_iq("prbs", seed=2)
    assert {value for pair in generate_iq("prbs", amplitude=123) for value in pair} == {-123, 123}


def test_chirp_phase_and_numerically_extreme_finite_sample_rate():
    # f0=0, f1=1 Hz, t_last=1s: final integrated phase is pi.
    assert generate_iq("chirp", 5, amplitude=100, frequency=0, chirp_end=1, sample_rate=4)[-1] == (-100, 0)
    assert len(generate_iq("chirp", 256, frequency=0, chirp_end=0, sample_rate=1e-300)) == 256
    assert generate_iq("complex_sine", 2, phase=1e300)


@pytest.mark.parametrize("kwargs", [{"count": 0}, {"count": 257.0}, {"count": True},
    {"amplitude": -1}, {"amplitude": 32768}, {"amplitude": float("nan")},
    {"frequency": float("inf")}, {"frequency": 11_000_000}, {"sample_rate": 0},
    {"sample_rate": float("nan")}, {"phase": float("inf")}, {"constant_i": 32768},
    {"constant_q": -32769}, {"seed": True}, {"seed": -1}, {"chirp_end": float("nan")}])
def test_generator_rejects_bad_values_without_overflow(kwargs):
    with pytest.raises(ValueError):
        generate_iq("complex_sine", **kwargs)


def test_chirp_end_respects_nyquist_and_unknown_kind_is_error():
    with pytest.raises(ValueError):
        generate_iq("chirp", chirp_end=10_000_001)
    with pytest.raises(ValueError):
        generate_iq("untrusted_random_noise")


def test_comparison_reports_pair_mismatches_and_integer_errors():
    result = compare_iq([(-32768, 32767), (12, -4), (0, 0)], [(32767, -32768), (12, -3), (0, 0)])
    assert result["mismatches"] == 2  # Pairs, not individual I/Q component errors.
    assert result["first_mismatch"] == 0
    assert result["max_abs_error"] == 65535
    assert result["error_i"] == [65535, 0, 0]
    assert result["error_q"] == [-65535, 1, 0]
    assert result["complete"] is True and result["exact"] is False
    assert compare_iq([(1, -2)], [(1, -2)])["exact"] is True
    assert compare_iq([], [])["exact"] is False


def test_comparison_missing_or_extra_samples_cannot_be_exact():
    result = compare_iq([(1, 2), (3, 4)], [(1, 2)])
    assert result["mismatches"] == 1 and result["first_mismatch"] == 1
    assert result["complete"] is False and result["exact"] is False
    assert result["expected_samples"] == 2 and result["actual_samples"] == 1
    assert compare_iq([(1, 2)], [(1, 2), (3, 4)])["mismatches"] == 1
    with pytest.raises(ValueError):
        compare_iq([(32768, 0)], [(0, 0)])


@pytest.mark.parametrize("endian", ["big", "little"])
def test_iq_csv_and_binary_round_trips(tmp_path, endian):
    values = [(-32768, 32767), (-1, 0), (123, -456)]
    csv_path, bin_path = tmp_path / "reference.csv", tmp_path / "reference.bin"
    export_iq_csv(csv_path, values)
    export_iq_bin(bin_path, values, endian)
    assert import_iq_csv(csv_path) == values
    assert import_iq_bin(bin_path, endian) == values
    assert csv_path.read_text().splitlines()[0] == "I,Q"


def test_original_stage_d_csv_headers_and_bom_are_supported(tmp_path):
    path = tmp_path / "actual_s2mm.csv"
    path.write_text("index,I_signed16,Q_signed16,IQ_u32_hex,source\n0,-32768,32767,0x80007FFF,FPGA_RX_S2MM\n", encoding="utf-8-sig")
    assert import_iq_csv(path) == [(-32768, 32767)]


@pytest.mark.parametrize("text", ["I,Q\n32768,0\n", "I,Q\n-32769,0\n", "I,Q\n1.0,2\n",
    "I,Q\nnan,2\n", "I,Q\n1\n", "I,Q\n1,2,3\n", "I,Q\n", "I,I,Q\n1,1,2\n",
    "index,amplitude\n0,123\n"])
def test_csv_refuses_out_of_range_malformed_or_ambiguous_samples(tmp_path, text):
    path = tmp_path / "invalid.csv"
    path.write_text(text, encoding="utf-8")
    with pytest.raises(ValueError):
        import_iq_csv(path)


def test_empty_truncated_and_unsupported_endian_binary_refused(tmp_path):
    path = tmp_path / "bad.bin"
    for raw in (b"", b"\x01\x02\x03"):
        path.write_bytes(raw)
        with pytest.raises(ValueError):
            import_iq_bin(path)
    with pytest.raises(ValueError):
        export_iq_bin(path, [(1, 2)], "native")
    with pytest.raises(ValueError):
        export_iq_csv(tmp_path / "empty.csv", [])
