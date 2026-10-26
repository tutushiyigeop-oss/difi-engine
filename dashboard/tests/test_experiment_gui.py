"""Qt integration tests use explicit Replay fixtures and never reach a board."""
import json
import math

import pytest
from PySide6.QtCore import QEventLoop, QTimer
from PySide6.QtWidgets import QTableWidgetItem

from dashboard.app.main_window import MainWindow
from dashboard.app.experiment.editors import IQEditor, PacketEditor
from dashboard.app.experiment.profile import parse_packet
from dashboard.app.experiment.exporter import export_experiment, load_experiment


def until(predicate, timeout=5000):
    loop, tick, deadline = QEventLoop(), QTimer(), QTimer()
    tick.setInterval(5)
    tick.timeout.connect(lambda: loop.quit() if predicate() else None)
    deadline.setSingleShot(True)
    deadline.timeout.connect(loop.quit)
    tick.start()
    deadline.start(timeout)
    if not predicate():
        loop.exec()
    tick.stop()
    deadline.stop()
    assert predicate(), "Qt operation did not complete"


def close_window(window):
    controller = window.stage_d.controller
    if controller.busy:
        controller.stop()
        until(lambda: not controller.busy)
    if controller.connected:
        controller.disconnect()
        until(lambda: not controller.busy)
    window.close()


def workspace(qapp, tmp_path, version=4):
    window = MainWindow(tmp_path)
    window.mode_combo.setCurrentIndex(2)
    panel = window.stage_d
    panel.replay_version.setCurrentIndex(0 if version == 4 else 1)
    return window, panel


def connect_ready(panel):
    assert panel.connect_board()
    until(lambda: not panel.controller.busy)
    assert panel.controller.connected
    if not panel._snapshot["status"].get("UTC"):
        assert panel.initialize_utc()
        until(lambda: not panel.controller.busy)
    assert panel.controller.state == "READY"


def test_stage_d_launch_is_network_free_and_legacy_modes_stay_isolated(qapp, tmp_path, monkeypatch):
    import socket
    monkeypatch.setattr(socket, "socket", lambda *a, **kw: (_ for _ in ()).throw(AssertionError("No network in Replay")))
    window, panel = workspace(qapp, tmp_path)
    try:
        assert panel.controller.state == "DISCONNECTED"
        assert len(panel.iq_editor.samples) == 256
        assert window.start_demo()
        until(lambda: panel.controller.session.state == "COMPLETED")
        assert all(record["source"] == "REPLAY" for record in panel.controller.session.transactions)
        assert not any(window.session.counts.values())
        window.mode_combo.setCurrentIndex(0)
        assert window.mode == "STAGED"
        window.source_combo.setCurrentIndex(1)
        assert window.source == "REPLAY"
        assert not panel.reset_session()
    finally:
        close_window(window)


@pytest.mark.parametrize("kind,size", [("DATA", 1052), ("CONTEXT", 108), ("VERSION", 44)])
def test_packet_editor_all_types_valid_and_frozen_fields_readonly(qapp, kind, size):
    editor = PacketEditor()
    editor.kind.setCurrentText(kind)
    assert editor.refresh_preview([(1, -1)] * 256)
    assert len(editor.packet) == size
    parsed = parse_packet(editor.packet)
    assert parsed["packet_type"] == kind
    assert parsed["fields"]["oui"] == "0x006A621E"
    assert editor.words.rowCount() == size // 4
    editor.close()


def test_generator_phase_and_reusable_preset_restore_exact_controls_and_samples(qapp):
    editor = IQEditor()
    editor.frequency.setValue(0)
    editor.phase.setValue(90)
    assert editor.samples[0] == (0, 12000)
    preset = editor.preset()
    assert preset["parameters"]["phase"] == pytest.approx(math.pi / 2)
    editor.phase.setValue(0)
    editor.load_preset(preset)
    assert editor.phase.value() == pytest.approx(90)
    assert editor.samples[0] == (0, 12000)
    editor.table.setItem(0, 1, QTableWidgetItem("-32768"))
    editor.table.setItem(0, 2, QTableWidgetItem("32767"))
    assert editor.samples[0] == (-32768, 32767)
    editor.table.setItem(0, 1, QTableWidgetItem("32768"))
    assert editor.samples[0] == (-32768, 32767)
    assert editor.error.text()
    editor.close()


@pytest.mark.parametrize("count", [1, 2, 64, 255, 256])
def test_custom_stage_d_runs_use_edited_iq_and_returned_byte_backed_waveforms(qapp, tmp_path, count):
    window, panel = workspace(qapp, tmp_path)
    try:
        panel.editor.fields["samples"].setValue(count)
        panel.iq_editor.set_samples([(-32768, 32767)] + [(100, -101)] * (count - 1), "Test PC fixture")
        connect_ready(panel)
        panel.rounds.setValue(1)
        assert panel.start_run()
        until(lambda: not panel.controller.busy)
        assert panel.controller.session.state == "COMPLETED"
        records = panel.controller.session.transactions
        assert records[-1]["direction"] == "RX"
        assert len(records[-1]["actual_iq"]) == count
        assert records[-1]["actual_iq"] == records[-1]["reference_iq"]
        assert "SIMULATED FPGA RX S2MM" in panel.waveform.waveform.source
        assert panel.waveform.waveform.i_samples[0] == -32768
        assert panel.waveform.waveform.q_samples[0] == 32767
        assert panel.waveform.table.rowCount() == count
        raw = panel.snapshot()
        paths = export_experiment(raw, tmp_path / "bundle")
        restored = load_experiment(paths["json"])
        assert restored["source"] == "REPLAY"
        assert restored["transactions"][-1]["actual_iq"] == records[-1]["actual_iq"]
    finally:
        close_window(window)


@pytest.mark.parametrize("kind", ["CONTEXT", "VERSION"])
def test_metadata_rx_and_no_false_iq_measurement(qapp, tmp_path, kind):
    window, panel = workspace(qapp, tmp_path)
    try:
        connect_ready(panel)
        panel.direction.setCurrentText("RX")
        panel.editor.kind.setCurrentText(kind)
        panel.rounds.setValue(2)
        assert panel.editor.packet
        assert panel.run_button.isEnabled()
        assert panel.start_run()
        until(lambda: not panel.controller.busy)
        assert panel.controller.session.state == "COMPLETED"
        records = panel.controller.session.transactions
        assert len(records) == 2
        assert [record["packets"][0]["parsed"]["sequence"] for record in records] == [0, 1]
        assert all(record["comparison"]["not_requested"] for record in records)
        assert panel.metrics["iq"].text() == "0"
        assert not panel.waveform.waveform.i_samples or "LOCAL PREVIEW" in panel.waveform.waveform.source
    finally:
        close_window(window)


def test_v03_ui_enforces_fixed_flow_and_v04_only_controls_are_disabled(qapp, tmp_path):
    window, panel = workspace(qapp, tmp_path, version=3)
    try:
        connect_ready(panel)
        assert not panel.apply_button.isEnabled()
        panel.editor.fields["samples"].setValue(2)
        assert panel.start_run()
        until(lambda: not panel.controller.busy)
        assert panel.controller.session.state == "COMPLETED"
        records = panel.controller.session.transactions
        assert len(records) == 4
        assert all(len(record["actual_iq"]) == 256 for record in records)
        assert "v0.3" in panel.restrictions.text()
    finally:
        close_window(window)


def test_new_run_resets_evidence_but_keeps_connection_and_exports_actual_config(qapp, tmp_path):
    window, panel = workspace(qapp, tmp_path)
    try:
        connect_ready(panel)
        panel.rounds.setValue(1)
        assert panel.start_run()
        until(lambda: not panel.controller.busy)
        old = panel.controller.session.id
        old_dir = panel.session_dir
        assert panel.start_run()
        until(lambda: not panel.controller.busy)
        assert panel.controller.session.id != old
        assert panel.session_dir != old_dir
        assert panel.controller.connected
        assert len(panel.controller.session.transactions) == 2
        # Editing a local unsent profile must not rewrite recorded applied config.
        panel.editor.fields["samples"].setValue(64)
        snapshot = panel.snapshot()
        assert snapshot["config"]["samples"] == 256
        assert snapshot["local_profile_preview"]["samples"] == 64
    finally:
        close_window(window)


def test_actual_trace_rejects_reference_array_without_returned_bytes(qapp, tmp_path):
    window, panel = workspace(qapp, tmp_path)
    try:
        panel.waveform.set_records([dict(direction="RX", actual_iq=[(1, 2)], reference_iq=[(1, 2)],
                                         source="REPLAY", fixture=True)], "fixture")
        panel.waveform.selector.setCurrentIndex(2)
        assert not panel.waveform.waveform.i_samples
        assert "rejected" in panel.waveform.metrics.text()
    finally:
        close_window(window)


def test_archive_reexport_preserves_recorded_config_status_and_offline_label(qapp, tmp_path):
    from dashboard.tests.test_stage_d_export import fixture_session

    window, panel = workspace(qapp, tmp_path)
    try:
        archive = fixture_session()
        archive["config"]["samples"] = 4
        panel._archive = archive
        panel._last_records = None
        panel._update_evidence()
        panel.waveform.selector.setCurrentIndex(2)
        assert "OFFLINE ARCHIVE" in panel.waveform.waveform.source
        frozen = panel.snapshot()
        assert frozen["config"] == archive["config"]
        assert frozen["status"] == archive["status"]
        assert frozen["offline_reanalysis"]
        paths = export_experiment(frozen, tmp_path / "reexport")
        assert load_experiment(paths["json"])["config"]["samples"] == 4
    finally:
        close_window(window)


def test_terminal_measurement_label_updates_without_new_packet(qapp, tmp_path):
    window, panel = workspace(qapp, tmp_path)
    try:
        assert panel.start_replay_demo()
        until(lambda: panel.controller.session.state == "COMPLETED")
        assert "COMPLETED" in panel.result_label.text()
        panel.controller.session.state = "STOPPED"
        panel._changed(panel.controller.snapshot())
        assert "STOPPED" in panel.result_label.text()
    finally:
        close_window(window)


def test_every_legal_sample_length_roundtrips_frozen_packet_profile():
    from dashboard.app.experiment.profile import ProfileConfig, build_packet

    for count in range(1, 257):
        samples = [(-32768, 32767)] * count
        raw = build_packet("DATA", ProfileConfig(samples=count), samples, sequence=count & 15)
        parsed = parse_packet(raw)
        assert len(raw) == (7 + count) * 4
        assert parsed["iq"] == samples
