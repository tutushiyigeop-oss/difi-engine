"""Byte-level experiment bundle tests; all datasets are simulated fixtures."""
import json

import pytest

from dashboard.app.experiment.replay import ReplayClient
from dashboard.app.experiment.profile import ProfileConfig
from dashboard.app.experiment.exporter import export_experiment, load_experiment


def fixture_session(state="COMPLETED"):
    client = ReplayClient()
    client.connect()
    client.configure(ProfileConfig(samples=4))
    client.initialize_utc(1700000000)
    tx = client.tx([(1, -1), (32767, -32768), (-2, 3), (0, 0)])
    transactions = [tx] + [client.rx(item["raw"]) for item in tx["packets"]]
    return {"id": "simulated-export-test", "source": "REPLAY", "state": state,
            "parameters": {}, "config": client.config.to_dict(), "status": client.status(),
            "capabilities": client.capabilities, "transactions": transactions, "events": [], "errors": []}


def test_export_reloads_actual_raw_bytes_and_fixture_provenance(tmp_path):
    session = fixture_session()
    paths = export_experiment(session, tmp_path)
    data = load_experiment(paths["json"])
    assert data["source"] == "REPLAY" and data["validated_from_bytes"]
    assert data["transactions"][0]["packets"][0]["raw"] == session["transactions"][0]["packets"][0]["raw"]
    assert data["transactions"][-1]["actual_iq"] == session["transactions"][-1]["actual_iq"]
    assert all(item["comparison"]["exact"] for item in data["transactions"])
    payload = json.loads(paths["json"].read_text(encoding="utf-8"))
    assert "REPLAY FIXTURE PASS" in payload["classification"]
    assert "NOT HARDWARE VALIDATION" in payload["classification"]
    assert list(tmp_path.rglob("*.csv")) and list(tmp_path.rglob("*.bin")) and list(tmp_path.rglob("*.difi"))
    assert "NOT HARDWARE VALIDATION" in paths["txt"].read_text(encoding="utf-8")


@pytest.mark.parametrize("state", ["STOPPED", "FAILED", "RUNNING", "READY", "DISCONNECTED"])
def test_partial_or_stopped_session_cannot_export_overall_pass(tmp_path, state):
    paths = export_experiment(fixture_session(state), tmp_path)
    payload = json.loads(paths["json"].read_text(encoding="utf-8"))
    assert "INCOMPLETE / FAILED" in payload["classification"]


def test_raw_file_tamper_is_rejected(tmp_path):
    paths = export_experiment(fixture_session(), tmp_path)
    raw = next(tmp_path.rglob("*.difi"))
    raw.write_bytes(raw.read_bytes()[:-1] + b"\xff")
    with pytest.raises(ValueError, match="changed"):
        load_experiment(paths["json"])


def test_iq_list_tamper_disagrees_with_raw_and_is_rejected(tmp_path):
    paths = export_experiment(fixture_session(), tmp_path)
    payload = json.loads(paths["json"].read_text(encoding="utf-8"))
    payload["session"]["transactions"][0]["actual_iq"][0][0] += 1
    paths["json"].write_text(json.dumps(payload), encoding="utf-8")
    with pytest.raises(ValueError, match="raw IQ bytes"):
        load_experiment(paths["json"])


def test_serialized_summary_is_recomputed_from_bytes(tmp_path):
    paths = export_experiment(fixture_session(), tmp_path)
    payload = json.loads(paths["json"].read_text(encoding="utf-8"))
    payload["session"]["transactions"][0]["comparison"]["mismatches"] = 999
    payload["session"]["transactions"][0]["packets"][0]["parsed"]["sequence"] = 7
    paths["json"].write_text(json.dumps(payload), encoding="utf-8")
    loaded = load_experiment(paths["json"])
    assert loaded["transactions"][0]["comparison"]["mismatches"] == 0
    assert loaded["transactions"][0]["packets"][0]["parsed"]["sequence"] == 0


def test_replay_cannot_be_relabelled_live(tmp_path):
    session = fixture_session()
    session["source"] = "LIVE"
    with pytest.raises(ValueError, match="provenance"):
        export_experiment(session, tmp_path)


def test_empty_bundle_is_not_pass_or_waveform_claim(tmp_path):
    paths = export_experiment({"source": "REPLAY", "state": "COMPLETED", "transactions": []}, tmp_path)
    assert "INCOMPLETE / FAILED" in paths["txt"].read_text(encoding="utf-8")
    assert "No captured transaction data" in paths["md"].read_text(encoding="utf-8")


def test_rx_numeric_values_without_received_raw_bytes_cannot_be_verified(tmp_path):
    session = fixture_session()
    transaction = session["transactions"][-1]
    transaction.pop("actual_iq_hex")
    transaction.pop("actual_iq_raw", None)
    with pytest.raises(ValueError, match="actual received S2MM byte evidence"):
        export_experiment(session, tmp_path)
