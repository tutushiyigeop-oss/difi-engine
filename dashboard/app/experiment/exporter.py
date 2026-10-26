"""Stage D evidence bundles with byte-validated reload and explicit provenance."""
from __future__ import annotations

from copy import deepcopy
import csv
import hashlib
import json
from pathlib import Path
from uuid import uuid4

from .iq import compare_iq
from .profile import decode_iq, encode_iq, parse_packet


def _raw(value):
    if isinstance(value, str):
        try:
            return bytes.fromhex(value)
        except ValueError as exc:
            raise ValueError("Invalid hexadecimal capture evidence") from exc
    return bytes(value)


def _json(value):
    if isinstance(value, bytes):
        return value.hex()
    if isinstance(value, dict):
        return {key: _json(item) for key, item in value.items()}
    if isinstance(value, (tuple, list)):
        return [_json(item) for item in value]
    if hasattr(value, "to_dict"):
        return _json(value.to_dict())
    return value


def _write(path, content):
    temporary = path.with_name("." + path.name + "." + uuid4().hex + ".tmp")
    try:
        temporary.write_text(content, encoding="utf-8")
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def _check_transaction(transaction, source):
    item = deepcopy(transaction)
    if item.get("source", source) != source or (source == "LIVE" and item.get("fixture")):
        raise ValueError("Live and Replay experiment provenance cannot be mixed")
    if source == "LIVE" and "REPLAY" in str(item.get("provenance", "")).upper():
        raise ValueError("Replay provenance cannot be classified as Live FPGA evidence")
    for packet in item.get("packets", []):
        raw = _raw(packet["raw"])
        digest = hashlib.sha256(raw).hexdigest()
        if packet.get("sha256", digest) != digest:
            raise ValueError("Raw DIFI checksum does not match the saved packet")
        packet.update(raw=raw, parsed=parse_packet(raw), sha256=digest)
    reference = list(map(tuple, item.get("reference_iq", [])))
    actual = list(map(tuple, item.get("actual_iq", [])))
    rx_data = (item.get("direction") == "RX"
               and any(packet["parsed"]["packet_type"] == "DATA" for packet in item.get("packets", [])))
    if rx_data and "actual_iq_raw" not in item and "actual_iq_hex" not in item:
        raise ValueError("RX Data requires actual received S2MM byte evidence; numeric IQ alone is insufficient")
    for key, values in (("reference_iq", reference), ("actual_iq", actual)):
        raw_key = key + "_hex"
        encoded = encode_iq(values)
        if raw_key in item and _raw(item[raw_key]) != encoded:
            raise ValueError(f"Saved {key} samples disagree with their raw IQ bytes")
        if key == "actual_iq" and "actual_iq_raw" in item and _raw(item["actual_iq_raw"]) != encoded:
            raise ValueError("Actual IQ samples disagree with the received raw S2MM payload")
        item[raw_key] = encoded.hex()
    if item.get("direction") == "TX":
        data = [packet for packet in item.get("packets", []) if packet["parsed"]["packet_type"] == "DATA"]
        if len(data) != 1 or list(map(tuple, data[0]["parsed"]["iq"])) != actual:
            raise ValueError("TX actual IQ is not backed by the raw FPGA Data capture")
    elif item.get("direction") == "RX":
        data = [packet for packet in item.get("packets", []) if packet["parsed"]["packet_type"] == "DATA"]
        if data and list(map(tuple, data[-1]["parsed"]["iq"])) != reference:
            raise ValueError("RX reference IQ disagrees with the transmitted DIFI bytes")
    item["reference_iq"], item["actual_iq"] = reference, actual
    metadata_only = (not reference and not actual and bool(item.get("packets"))
                     and all(packet["parsed"]["packet_type"] != "DATA" for packet in item["packets"]))
    if metadata_only and item.get("verification", {}).get("META") != 1:
        raise ValueError("Metadata transaction lacks an explicit successful META acknowledgement")
    item["comparison"] = ({"complete": True, "exact": True, "not_requested": True,
                           "mismatches": 0, "expected_samples": 0, "actual_samples": 0}
                          if metadata_only else compare_iq(reference, actual))
    item["validated_from_bytes"] = True
    return item


def export_experiment(session, destination: Path) -> dict[str, Path]:
    data = session.to_dict() if hasattr(session, "to_dict") else deepcopy(session)
    source = str(data.get("source", "")).upper()
    if source not in {"LIVE", "REPLAY"}:
        raise ValueError("Experiment source must be LIVE or REPLAY")
    data["transactions"] = [_check_transaction(item, source) for item in data.get("transactions", [])]
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    passed = (data.get("state") == "COMPLETED" and bool(data["transactions"])
              and all(item["comparison"]["exact"] for item in data["transactions"]) and not data.get("errors"))
    classification = ("REPLAY FIXTURE " if source == "REPLAY" else "LIVE FPGA EVIDENCE ") + ("PASS" if passed else "INCOMPLETE / FAILED")
    if source == "REPLAY":
        classification += " — NOT HARDWARE VALIDATION"
    paths = {kind: destination / f"experiment.{kind}" for kind in ("json", "txt", "md")}
    manifest = []
    for index, transaction in enumerate(data["transactions"]):
        folder = destination / f"transaction_{index:04d}_{transaction['direction'].lower()}"
        folder.mkdir(exist_ok=True)
        for number, packet in enumerate(transaction.get("packets", [])):
            path = folder / f"packet_{number:02d}_{packet['parsed']['packet_type'].lower()}.difi"
            path.write_bytes(packet["raw"])
            manifest.append({"path": str(path.relative_to(destination)).replace("\\", "/"), "sha256": hashlib.sha256(packet["raw"]).hexdigest()})
        for label in ("reference_iq", "actual_iq"):
            pairs = transaction.get(label, [])
            if not pairs:
                continue
            binary = folder / f"{label}.bin"
            binary.write_bytes(encode_iq(pairs))
            manifest.append({"path": str(binary.relative_to(destination)).replace("\\", "/"), "sha256": hashlib.sha256(binary.read_bytes()).hexdigest()})
            with (folder / f"{label}.csv").open("w", encoding="utf-8", newline="") as stream:
                writer = csv.writer(stream)
                writer.writerow(("index", "I", "Q", "source", "provenance"))
                writer.writerows((n, i, q, source, transaction.get("provenance", "")) for n, (i, q) in enumerate(pairs))
        with (folder / "comparison.csv").open("w", encoding="utf-8", newline="") as stream:
            writer = csv.writer(stream)
            writer.writerow(("index", "reference_I", "reference_Q", "actual_I", "actual_Q", "error_I", "error_Q"))
            for n in range(max(len(transaction.get("reference_iq", [])), len(transaction.get("actual_iq", [])))):
                reference = transaction.get("reference_iq", [])
                actual = transaction.get("actual_iq", [])
                a, b = reference[n] if n < len(reference) else (None, None), actual[n] if n < len(actual) else (None, None)
                writer.writerow((n, *a, *b, b[0] - a[0] if None not in (a[0], b[0]) else "", b[1] - a[1] if None not in (a[1], b[1]) else ""))
    payload = {"schema_version": 1, "classification": classification, "source": source, "session": data, "files": manifest}
    text = [classification, "Stage D software half duplex; one direction is active at a time.", ""]
    for event in data.get("events", []):
        event = event.to_dict() if hasattr(event, "to_dict") else event
        text.append(f"{event.get('timestamp', '')} [{source}] {event.get('kind', '')} {json.dumps(_json(event.get('data', {})), ensure_ascii=False)}")
    report = ["# Stage D experiment evidence", "", f"**{classification}**", "",
              "Replay datasets are simulated fixtures. Live TX waveform comes from raw FPGA TX DIFI capture; Live RX waveform comes from actual FPGA S2MM IQ bytes.", "",
              "| Transaction | Direction | Provenance | Actual IQ | Mismatches |", "| --- | --- | --- | ---: | ---: |"]
    for item in data["transactions"]:
        report.append(f"| {item.get('transaction')} | {item.get('direction')} | {item.get('provenance')} | {len(item.get('actual_iq', []))} | {item['comparison']['mismatches']} |")
    if not data["transactions"]:
        report.extend(["", "No captured transaction data. No waveform or hardware PASS is claimed."])
    report.extend(["", "## Configuration and observed status", "", "```json",
                   json.dumps(_json({"parameters": data.get("parameters", {}), "config": data.get("config", {}), "status": data.get("status", {}), "capabilities": data.get("capabilities", {})}), indent=2), "```", "",
                   "GPIO fields are available only when explicitly returned by the firmware STATUS. Archived B5/B6 measurements are not current transaction throughput.", ""])
    _write(paths["txt"], "\n".join(text))
    _write(paths["md"], "\n".join(report))
    _write(paths["json"], json.dumps(_json(payload), indent=2, ensure_ascii=False))
    return paths


def load_experiment(path: Path) -> dict:
    path = Path(path)
    if path.is_dir():
        path = path / "experiment.json"
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema_version") != 1 or payload.get("source") not in {"LIVE", "REPLAY"}:
        raise ValueError("Unsupported experiment export schema / provenance")
    data = payload["session"]
    if data.get("source") != payload["source"]:
        raise ValueError("Conflicting experiment provenance")
    for entry in payload.get("files", []):
        target = (path.parent / entry["path"]).resolve()
        if not target.is_relative_to(path.parent.resolve()):
            raise ValueError("Export manifest path escapes its evidence directory")
        if not target.is_file() or hashlib.sha256(target.read_bytes()).hexdigest() != entry["sha256"]:
            raise ValueError("Exported raw evidence file is missing or has changed")
    data["transactions"] = [_check_transaction(item, payload["source"]) for item in data.get("transactions", [])]
    data["validated_from_bytes"] = True
    return data
