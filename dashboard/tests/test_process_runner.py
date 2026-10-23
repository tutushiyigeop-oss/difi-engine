"""QProcess tests use helper Python children and never execute board tools."""
import sys

import pytest
from PySide6.QtCore import QEventLoop, QTimer

from dashboard.app.config import DemoConfig, build_command
from dashboard.app.models.session import Session
from dashboard.app.services.process_runner import ProcessRunner, describe_process_error


def spin_until(qapp, condition, seconds=6):
    if condition():
        return
    loop = QEventLoop()
    check = QTimer()
    check.setInterval(1)
    check.timeout.connect(lambda: loop.quit() if condition() else None)
    deadline = QTimer()
    deadline.setSingleShot(True)
    deadline.timeout.connect(loop.quit)
    check.start()
    deadline.start(int(seconds * 1000))
    loop.exec()
    check.stop()
    deadline.stop()
    assert condition(), "Child process did not complete within the test deadline"


def helper_command(tmp_path, text):
    script = tmp_path / "fake_checker.py"
    script.write_text(text, encoding="utf-8")
    return [sys.executable, "-u", str(script)]


def test_incremental_stdout_stderr_unicode_and_final_unterminated_line(qapp, monkeypatch, tmp_path):
    argv = helper_command(tmp_path, "import os, time\nos.write(1, b'[PA')\ntime.sleep(.025)\nos.write(1, b'SS] #00 type=5 seq= 0 words= 11 bytes=  44\\n')\nos.write(1, b'\\xe6')\ntime.sleep(.025)\nos.write(1, b'\\xb5\\x8b\\xe8\\xaf\\x95\\n')\nos.write(2, b'original stderr without newline')\n")
    runner = ProcessRunner()
    monkeypatch.setattr(runner, "_build_command", lambda *args: argv)
    messages, events, finishes = [], [], []
    runner.log.connect(lambda level, source, message: messages.append((level, source, message)))
    runner.event.connect(events.append)
    runner.finished.connect(lambda code, stopped: finishes.append((code, stopped)))
    assert runner.start("B5", {}, tmp_path)
    spin_until(qapp, lambda: not runner.running)
    assert finishes == [(0, False)]
    assert len([event for event in events if event.kind == "PACKET_PASS"]) == 1
    assert any(message == "测试" for _, _, message in messages)
    assert any(source.endswith("stderr") and message == "original stderr without newline" for _, source, message in messages)
    assert runner._process is None


def test_nonzero_exit_cannot_finish_session_as_pass(qapp, monkeypatch, tmp_path):
    argv = helper_command(tmp_path, "print('[PASS] #00 type=5 seq= 0 words= 11 bytes=  44')\nraise SystemExit(7)\n")
    runner = ProcessRunner()
    monkeypatch.setattr(runner, "_build_command", lambda *args: argv)
    session = Session("B5", "LIVE", {})
    session.start()
    runner.event.connect(session.apply)
    runner.finished.connect(session.finish)
    assert runner.start("B5", {}, tmp_path)
    spin_until(qapp, lambda: not runner.running)
    assert session.exit_code == 7
    assert session.state == "FAILED"
    assert session.total_packets == 1


@pytest.mark.parametrize("mode,output,hint", [
    ("B5", "[FAIL] [WinError 10048] Only one usage of each socket address is normally permitted", "port is already in use"),
    ("B5", "[FAIL] [WinError 10049] The requested address is not valid in its context", "PC IP is not assigned"),
    ("B5", "[FAIL] timeout waiting packet #0; received 0/22. Check board UART, PC IP/firewall.", "No expected board response"),
    ("B6", "[FAIL] timed out", "No expected board response"),
    ("B6", "[FAIL] Board STATUS missing NEXT_CONTEXT; wrong ELF?", "matching B6 bitstream"),
    ("B6", "[FAIL] data: ACK FAIL ROUND=14 SEQ=14 IQ=0 (expected ACK PASS ROUND=14 SEQ=14 IQ=256)", ""),
])
def test_child_reported_network_and_ack_failures_never_generate_pass(qapp, monkeypatch, tmp_path, mode, output, hint):
    argv = helper_command(tmp_path, f"print({output!r}, flush=True)\nraise SystemExit(2)\n")
    runner = ProcessRunner()
    monkeypatch.setattr(runner, "_build_command", lambda *args: argv)
    session = Session(mode, "LIVE", {})
    session.start()
    events, logs, finishes = [], [], []
    runner.event.connect(session.apply)
    runner.event.connect(events.append)
    runner.log.connect(lambda level, source, message: logs.append(message))
    runner.finished.connect(session.finish)
    runner.finished.connect(lambda code, stopped: finishes.append((code, stopped)))
    assert runner.start(mode, {}, tmp_path)
    spin_until(qapp, lambda: not runner.running)
    assert finishes == [(2, False)]
    assert session.state == "FAILED"
    assert session.total_packets == 0
    assert session.verified_iq == 0
    assert not any(event.kind == "PACKET_PASS" for event in events)
    assert output in logs
    if hint:
        assert any(hint in message for message in logs)


def test_abnormally_terminated_child_is_error_and_finishes_once(qapp, monkeypatch, tmp_path):
    # Terminate only this helper process, without Windows crash-report dialogs or
    # POSIX core dumps. The Windows exception-range status exercises CrashExit.
    text = """import os, signal
print('[INFO] synthetic helper before abnormal termination', flush=True)
if os.name == 'nt':
    import ctypes
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.GetCurrentProcess.restype = ctypes.c_void_p
    kernel.TerminateProcess.argtypes = [ctypes.c_void_p, ctypes.c_uint]
    kernel.TerminateProcess(kernel.GetCurrentProcess(), 0xC0000005)
else:
    os.kill(os.getpid(), signal.SIGKILL)
"""
    argv = helper_command(tmp_path, text)
    runner = ProcessRunner()
    monkeypatch.setattr(runner, "_build_command", lambda *args: argv)
    events, finishes = [], []
    session = Session("B6", "LIVE", {})
    session.start()
    runner.event.connect(events.append)
    runner.event.connect(session.apply)
    runner.finished.connect(session.finish)
    runner.finished.connect(lambda code, stopped: finishes.append((code, stopped)))
    assert runner.start("B6", {}, tmp_path)
    spin_until(qapp, lambda: not runner.running)
    assert len(finishes) == 1
    assert finishes[0][0] != 0
    assert finishes[0][1] is False
    assert session.state == "FAILED"
    assert any(event.kind == "SESSION_ERROR" for event in events)


def test_stop_duplicate_start_and_ui_timer_responsiveness(qapp, monkeypatch, tmp_path):
    argv = helper_command(tmp_path, "import time\nprint('[INFO] child started', flush=True)\ntime.sleep(30)\n")
    runner = ProcessRunner()
    monkeypatch.setattr(runner, "_build_command", lambda *args: argv)
    finishes, heartbeats = [], []
    runner.finished.connect(lambda code, stopped: finishes.append((code, stopped)))
    timer = QTimer()
    timer.setInterval(1)
    timer.timeout.connect(lambda: heartbeats.append(True))
    timer.start()
    assert runner.start("B6", {}, tmp_path)
    assert not runner.start("B6", {}, tmp_path)
    spin_until(qapp, lambda: len(heartbeats) >= 4)
    runner.stop()
    runner.stop()
    spin_until(qapp, lambda: not runner.running)
    timer.stop()
    assert len(finishes) == 1
    assert finishes[0][1] is True
    assert len(heartbeats) >= 4
    assert not runner._kill_timer.isActive()
    assert runner._process is None


def test_failed_to_start_finishes_once_and_has_error_event(qapp, monkeypatch, tmp_path):
    runner = ProcessRunner()
    monkeypatch.setattr(runner, "_build_command", lambda *args: [str(tmp_path / "missing_python.exe")])
    finishes, events = [], []
    runner.finished.connect(lambda code, stopped: finishes.append((code, stopped)))
    runner.event.connect(events.append)
    assert runner.start("B6", {}, tmp_path)
    spin_until(qapp, lambda: not runner.running)
    assert finishes == [(-1, False)]
    assert any(event.kind == "SESSION_ERROR" for event in events)


def test_stdout_pressure_yields_to_ui_and_finishes_after_all_lines(qapp, monkeypatch, tmp_path):
    argv = helper_command(tmp_path, "import sys\nsys.stdout.write(''.join('[INFO] fixture line %d\\n' % n for n in range(7000)))\nsys.stdout.flush()\n")
    runner = ProcessRunner()
    monkeypatch.setattr(runner, "_build_command", lambda *args: argv)
    lines, beats, finishes = [], [], []
    runner.log.connect(lambda level, source, message: lines.append(message) if message.startswith("[INFO] fixture line") else None)
    runner.finished.connect(lambda code, stopped: finishes.append((code, stopped, len(lines))))
    timer = QTimer()
    timer.setInterval(1)
    timer.timeout.connect(lambda: beats.append(len(lines)))
    timer.start()
    assert runner.start("B6", {}, tmp_path)
    spin_until(qapp, lambda: not runner.running)
    timer.stop()
    assert finishes == [(0, False, 7000)]
    assert len(lines) == 7000
    assert any(0 < count < 7000 for count in beats)


def test_stop_during_final_line_drain_is_preserved(qapp, monkeypatch, tmp_path):
    argv = helper_command(tmp_path, "import sys\nsys.stdout.write(''.join('[INFO] drain line %d\\n' % n for n in range(7000)))\nsys.stdout.flush()\n")
    runner = ProcessRunner()
    monkeypatch.setattr(runner, "_build_command", lambda *args: argv)
    # Hold dispatch until the child has actually exited, then release it. This
    # makes the final-drain case independent of machine speed and pipe timing.
    runner._dispatch_timer.setInterval(60_000)
    lines, stop_points, finishes = [], [], []

    def on_line(level, source, message):
        if not message.startswith("[INFO] drain line"):
            return
        lines.append(message)
        if runner._process is None and not stop_points:
            stop_points.append(len(lines))
            runner.stop()

    runner.log.connect(on_line)
    runner.finished.connect(lambda code, stopped: finishes.append((code, stopped)))
    assert runner.start("B6", {}, tmp_path)
    runner._process.finished.connect(lambda *_: runner._dispatch_timer.setInterval(0))
    spin_until(qapp, lambda: not runner.running)
    assert stop_points, "The helper must finish while queued lines remain for this regression"
    assert finishes == [(0, True)]
    assert len(lines) == 7000


def test_invalid_start_does_not_create_child_or_keep_old_capture(qapp, tmp_path):
    runner = ProcessRunner()
    runner.capture_path = tmp_path / "old.bin"
    events = []
    runner.event.connect(events.append)
    assert not runner.start("B5", {"board": "not-an-ip"}, tmp_path)
    assert not runner.running
    assert runner._process is None
    assert runner.capture_path is None
    assert [event.kind for event in events] == ["SESSION_ERROR"]


def test_command_configuration_matches_original_tools_without_starting_network(tmp_path):
    b5 = build_command("B5", DemoConfig.for_mode("B5").to_dict(), tmp_path)
    b6 = build_command("B6", DemoConfig.for_mode("B6").to_dict(), tmp_path)
    assert b5[:2] == [sys.executable, "-u"]
    assert b5[2].endswith("difi_udp_receiver.py")
    assert b5[b5.index("--pc-ip") + 1] == "192.168.1.20"
    assert b5[b5.index("--timeout") + 1] == "10.0"
    assert b5[b5.index("--output") + 1] == str(tmp_path.resolve() / "b5_capture.bin")
    assert b6[2].endswith("difi_b6_three_types.py")
    assert b6[b6.index("--timeout") + 1] == "5.0"
    assert b6[b6.index("--types") + 1] == "version,context,data"
    assert "--output" not in b6


@pytest.mark.parametrize("parameters", [
    {"board": "board.local"}, {"local_ip": "999.1.2.3"}, {"port": 0},
    {"port": 65536}, {"port": 1.2}, {"rounds": 0}, {"rounds": 1001},
    {"timeout": 0}, {"timeout": float("nan")}, {"types": "version,version"},
    {"types": "data,"}, {"types": "bogus"},
])
def test_invalid_settings_are_rejected_before_process_creation(parameters):
    with pytest.raises(ValueError):
        DemoConfig.from_dict(parameters, "B6")


@pytest.mark.parametrize("message,expected", [
    ("[WinError 10048] address already in use", "port"),
    ("[WinError 10049] requested address", "PC IP"),
    ("timeout waiting packet #0", "UTC"),
    ("Board STATUS missing NEXT_CONTEXT; wrong ELF?", "ELF"),
])
def test_actionable_network_error_messages(message, expected):
    assert expected in describe_process_error(message)
