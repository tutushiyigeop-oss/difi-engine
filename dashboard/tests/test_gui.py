"""Real Qt widget/process tests, using offline fixtures and fake tool output only."""
import json
import sys

from PySide6.QtCore import QEventLoop, QTimer

from dashboard.app.main_window import MainWindow, SettingsDialog
from dashboard.app.services.result_exporter import export_session
from dashboard.app.theme import apply_theme


def until(predicate, timeout=7000):
    loop = QEventLoop()
    tick = QTimer()
    deadline = QTimer()
    deadline.setSingleShot(True)
    tick.setInterval(10)
    tick.timeout.connect(lambda: loop.quit() if predicate() else None)
    deadline.timeout.connect(loop.quit)
    deadline.start(timeout)
    tick.start()
    if not predicate():
        loop.exec()
    tick.stop()
    deadline.stop()
    assert predicate(), "Qt operation did not complete before test timeout"


def test_gui_idle_and_render_without_network(qapp, tmp_path, monkeypatch):
    import socket
    monkeypatch.setattr(socket, "socket", lambda *a, **kw: (_ for _ in ()).throw(AssertionError("No UDP allowed")))
    apply_theme(qapp)
    window = MainWindow(tmp_path)
    window.resize(1280, 800)
    window.show()
    qapp.processEvents()
    assert window.session.state == "IDLE"
    assert window.source == "REPLAY"
    assert not window.running
    assert sum(window.session.counts.values()) == 0
    assert window.session.verified_iq == 0
    assert window.grab().save(str(tmp_path / "gui.png"))
    window.close()


def test_gui_replay_stop_repeat_reset_and_mode_guard(qapp, tmp_path):
    window = MainWindow(tmp_path)
    window.show()
    window.replay_service._timer.setInterval(20)
    assert window.start_demo()
    assert not window.start_demo()
    assert not window.reset_session()
    window.mode_combo.setCurrentIndex(1)
    assert window.mode == "B5"
    until(lambda: len(window.session.packets) >= 2)
    window.stop_demo()
    until(lambda: window.session.state == "STOPPED")
    assert not window.running
    assert window.reset_session()
    assert window.session.state == "IDLE"
    assert window.session.verified_iq == 0
    assert window.session.mismatches is None
    assert window.session.counts == {"VERSION": 0, "CONTEXT": 0, "DATA": 0}
    window.close()


def test_gui_complete_b5_capture_and_export(qapp, tmp_path):
    window = MainWindow(tmp_path)
    window.replay_service._timer.setInterval(1)
    window.show()
    assert window.start_demo()
    until(lambda: window.session.state == "COMPLETED")
    until(lambda: window._wave_future is None)
    assert window.session.verified_iq == 5120
    assert window.session.payload_bytes == 21192
    paths = export_session(window.session, window.raw_logs, tmp_path / "export")
    document = json.loads(paths["json"].read_text(encoding="utf-8"))
    assert document["session"]["source"] == "REPLAY"
    assert "not a hardware test" in document["classification"]
    assert "SIMULATED" in paths["txt"].read_text(encoding="utf-8")
    until(lambda: bool(list(window.session_dir.glob("*.json"))))
    assert (window.session_dir / "raw.log.txt").is_file()
    # Clearing the console must preserve evidence in subsequent exports.
    before = len(window.raw_logs)
    window.clear_log()
    assert len(window.raw_logs) == before
    window.close()


def test_gui_b6_replay_nonzero_status_and_failure_clears_pass(qapp, tmp_path):
    window = MainWindow(tmp_path)
    window.replay_service._timer.setInterval(1)
    window.mode_combo.setCurrentIndex(1)
    assert window.start_demo()
    until(lambda: window.session.state == "COMPLETED")
    assert window.session.board_status["NEXT_ROUND"] == 14
    assert window.session.verified_iq == 5120
    window.source_combo.setCurrentIndex(1)
    assert window.session.state == "IDLE"
    assert window.session.verified_iq == 0
    window.process_runner._build_command = lambda *a: [
        sys.executable, "-u", "-c",
        "print('[FAIL] timed out waiting for board STATUS; wrong ELF?'); raise SystemExit(2)"
    ]
    assert window.start_demo()
    until(lambda: window.session.state == "FAILED")
    assert window.session.exit_code == 2
    assert window.session.verified_iq == 0
    assert not any(window.session.counts.values())
    assert any("No expected board response" in entry["message"] for entry in window.raw_logs)
    window.close()


def test_settings_validation_without_network(qapp, tmp_path):
    window = MainWindow(tmp_path)
    dialog = SettingsDialog("B6", window.configs["B6"])
    dialog.board.setText("bad-ip")
    dialog.validate_accept()
    assert "IPv4" in dialog.error.text()
    dialog.board.setText("192.168.1.10")
    dialog.types.setText("data,data")
    dialog.validate_accept()
    assert "unique" in dialog.error.text()
    dialog.close()
    window.close()


def test_b5_replay_early_stop_never_displays_future_fixture_iq(qapp, tmp_path):
    from scripts.verify.tools.difi_b6_sender import expected_iq

    window = MainWindow(tmp_path)
    window.replay_service._timer.setInterval(25)
    assert window.start_demo()
    until(lambda: window.session.counts["DATA"] >= 2)
    window.stop_demo()
    until(lambda: window.session.state == "STOPPED")
    until(lambda: window._wave_future is None)
    passed = [packet for packet in window.session.packets if packet["packet_type"] == "DATA" and packet["verified"]]
    assert len(passed) < 20
    last_round = passed[-1]["round"]
    word = expected_iq(last_round, 10)
    signed = lambda n: n - 65536 if n & 0x8000 else n
    assert window.waveform.i_samples[10] == signed(word >> 16)
    assert window.waveform.q_samples[10] == signed(word & 65535)
    assert "SIMULATED" in window.waveform.source
    window.close()


def test_export_button_writes_snapshot_off_thread(qapp, tmp_path, monkeypatch):
    from PySide6.QtWidgets import QFileDialog

    window = MainWindow(tmp_path / "sessions")
    window.show()
    monkeypatch.setattr(QFileDialog, "getExistingDirectory", lambda *a, **kw: str(tmp_path / "exports"))
    window.export_result()
    until(lambda: window._export_future is None)
    folder = next((tmp_path / "exports").iterdir())
    assert (folder / "dashboard.png").is_file()
    assert list(folder.glob("*.json"))
    assert any("Saved TXT" in row["message"] for row in window.raw_logs)
    window.close()
