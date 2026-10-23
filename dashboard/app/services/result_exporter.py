"""Portable evidence exports with explicit Live/Replay provenance."""
from __future__ import annotations

from datetime import datetime, timezone
import json
from pathlib import Path
import re
from typing import Any
from uuid import uuid4


def _safe_name(value: Any) -> str:
    return re.sub(r"[^A-Za-z0-9_-]", "_", str(value))[:96]


def _atomic_text(path: Path, content: str) -> None:
    temporary = path.with_name(f".{path.name}.{uuid4().hex}.tmp")
    try:
        temporary.write_text(content, encoding="utf-8", newline="\n")
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def export_session(session: Any, logs: list[dict[str, Any]], destination: Path) -> dict[str, Path]:
    """Write original messages, structured evidence and a human-readable report."""
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    data = dict(session) if isinstance(session, dict) else session.to_dict()
    replay = str(data.get("source", "")).upper() == "REPLAY"
    completed = data.get("state") == "COMPLETED"
    classification = ("REPLAY PASS (simulated fixture; not a hardware test)" if completed else "REPLAY " + str(data.get("state"))) if replay else (
        "LIVE HARDWARE PASS (validated tool output and process exit)" if completed else "LIVE " + str(data.get("state")))
    trust_notice = ("SIMULATED TEST FIXTURE / OFFLINE. No physical FPGA validation was performed by this replay."
                    if replay else "Live verification evidence from the original B5/B6 tool. Only confirmed packet validation contributes to totals.")
    basename = f"{_safe_name(data.get('mode', 'DIFI'))}_{_safe_name(data.get('source', 'UNKNOWN'))}_{_safe_name(data.get('id', uuid4().hex))}"
    paths = {suffix: destination / f"{basename}.{suffix}" for suffix in ("txt", "json", "md")}
    raw_lines = [f"DIFI ENGINE CONTROL CENTER — {classification}", trust_notice,
                 f"Session: {data.get('id')} | Mode: {data.get('mode')} | Source: {data.get('source')}",
                 f"Started: {data.get('started_at')} | Ended: {data.get('ended_at')} | Exit code: {data.get('exit_code')}", ""]
    for entry in logs:
        raw_lines.append(f"{entry.get('timestamp', entry.get('time', ''))} [{entry.get('source', data.get('source', ''))}] "
                         f"[{entry.get('level', 'INFO')}] {entry.get('message', entry.get('text', ''))}")
    confirmed_data = int(data.get("counts", {}).get("DATA", 0)) > 0
    if data.get("mode") == "B5":
        waveform_source = (("Synthetic test fixture capture" if replay else "Received and validated DIFI UDP payload")
                           if confirmed_data else "No samples available (no confirmed Data packet)")
    else:
        waveform_source = ("Golden Reference; FPGA IQ samples are not returned in UDP ACKs" if confirmed_data
                           else "No Golden Reference displayed (no confirmed Data packet)")
    structured = {"schema_version": 1, "exported_at": datetime.now(timezone.utc).isoformat(),
                  "classification": classification, "provenance_notice": trust_notice,
                  "waveform_source": waveform_source,
                  "session": data, "logs": list(logs)}
    counts = data.get("counts", {})
    missing = "Not Observable"
    mismatches = data.get("mismatches")
    mismatch_display = (f"≥{mismatches} (observed minimum)" if data.get("mismatches_are_minimum")
                        and mismatches is not None else mismatches if mismatches is not None else missing)
    report = ["# DIFI ENGINE CONTROL CENTER", "", f"**Result: {classification}**", "", trust_notice, "",
              f"- Session: `{data.get('id')}`", f"- Mode / source: {data.get('mode')} / {data.get('source')}",
              f"- State: {data.get('state')}", f"- Started: {data.get('started_at') or 'N/A'}",
              f"- Ended: {data.get('ended_at') or 'N/A'}", f"- Process exit code: {data.get('exit_code')}", "",
              "## Observed verification", "", "| Measurement | Observed |", "| --- | ---: |",
              f"| Version packets | {counts.get('VERSION', 0)} |", f"| Context packets | {counts.get('CONTEXT', 0)} |",
              f"| Data packets | {counts.get('DATA', 0)} |", f"| Total packets | {data.get('total_packets', 0)} |",
              f"| UDP payload bytes | {data.get('payload_bytes', 0)} |",
              f"| Verified IQ samples | {data.get('verified_iq', 0)} |",
              f"| IQ mismatches | {mismatch_display} |",
              f"| Expected IQ samples (target) | {data.get('expected_iq', 0)} |",
              f"| GPIO error counter / changed flag | {missing} |", "",
              f"Waveform source: {waveform_source}.", "",
              "B5 IQ verification uses the receiver payload checker. B6 IQ verification uses the board ACK; displayed B6 waveform is Golden Reference.", "",
              "## Parameters", "", "```json", json.dumps(data.get("parameters", {}), indent=2, ensure_ascii=False), "```", "",
              "## Board STATUS", "", "```json", json.dumps(data.get("board_status", {}), indent=2, ensure_ascii=False), "```", "",
              "## Errors and sequence observations", "", "```json",
              json.dumps({"errors": data.get("errors", []), "sequence_issues": data.get("sequence_issues", [])}, indent=2, ensure_ascii=False), "```", "",
              f"Original log messages: [{paths['txt'].name}]({paths['txt'].name}).",
              f"Complete packets, events and timestamps: [{paths['json'].name}]({paths['json'].name}).", "",
              "Archived performance figures in the dashboard are historical measurements and do not describe this UDP session.", ""]
    _atomic_text(paths["txt"], "\n".join(raw_lines) + "\n")
    _atomic_text(paths["json"], json.dumps(structured, indent=2, ensure_ascii=False, default=str) + "\n")
    _atomic_text(paths["md"], "\n".join(report))
    return paths
