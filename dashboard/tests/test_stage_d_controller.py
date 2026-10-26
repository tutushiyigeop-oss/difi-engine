"""Native Qt orchestration tests using explicitly network-free Replay fixtures."""
import socket
import json

from PySide6.QtCore import QEventLoop, QTimer, QThread

from dashboard.app.experiment.controller import ExperimentController
from dashboard.app.experiment.profile import ProfileConfig, build_packet
from dashboard.app.experiment.client import legacy_iq


def until(condition, timeout=5000):
    if condition():
        return
    loop, tick, deadline = QEventLoop(), QTimer(), QTimer()
    tick.setInterval(2)
    tick.timeout.connect(lambda: loop.quit() if condition() else None)
    deadline.setSingleShot(True)
    deadline.timeout.connect(loop.quit)
    tick.start()
    deadline.start(timeout)
    loop.exec()
    tick.stop()
    deadline.stop()
    assert condition(), "Experiment worker did not finish before deadline"


def connect_replay(controller, version=4):
    assert controller.connect_board({"replay_version": version}, source="REPLAY")
    until(lambda: not controller.busy)
    assert controller.connected
    assert controller.initialize_utc(1700000000, 123)
    until(lambda: not controller.busy)


def cleanup(controller):
    if controller.connected:
        assert controller.disconnect()
        until(lambda: not controller.busy)
    controller._timer.stop()
    controller.shutdown()


def test_replay_controller_no_network_alternates_and_updates_on_qt_thread(qapp, monkeypatch):
    monkeypatch.setattr(socket, "socket", lambda *a, **k: (_ for _ in ()).throw(AssertionError("No UDP in Replay")))
    controller = ExperimentController()
    phases, signals = [], []
    controller.changed.connect(lambda snapshot: phases.append(snapshot["state"]))
    controller.event.connect(lambda event: signals.append(QThread.currentThread() == qapp.thread()))
    connect_replay(controller)
    config = ProfileConfig(samples=4)
    assert controller.run("TX", [(1, -1)] * 4, rounds=2, alternate=True, config=config)
    assert not controller.run("TX", [(1, -1)] * 4)
    assert not controller.reset()
    until(lambda: not controller.busy)
    assert controller.session.state == "COMPLETED"
    assert len(controller.session.transactions) == 6
    assert all(item["comparison"]["exact"] for item in controller.session.transactions)
    assert all(item["source"] == "REPLAY" and item["fixture"] for item in controller.session.transactions)
    assert "TX_ACTIVE" in phases and "RX_ACTIVE" in phases
    assert signals and all(signals)
    cleanup(controller)


def test_repeated_rx_uses_independent_managed_sequence(qapp):
    controller = ExperimentController()
    connect_replay(controller)
    config = ProfileConfig(samples=4)
    packet = build_packet("DATA", config, [(3, -4)] * 4, sequence=0)
    assert controller.run("RX", None, packet=packet, rounds=3, config=config)
    until(lambda: not controller.busy)
    assert controller.session.state == "COMPLETED"
    assert [item["packets"][0]["parsed"]["sequence"] for item in controller.session.transactions] == [0, 1, 2]
    assert controller.snapshot()["status"]["RX_DATA_NEXT"] == 3
    cleanup(controller)


def test_metadata_has_protocol_verification_without_fake_iq(qapp):
    controller = ExperimentController()
    connect_replay(controller)
    packet = build_packet("VERSION", ProfileConfig(), sequence=0)
    assert controller.run("RX", [], packet=packet, config=ProfileConfig())
    until(lambda: not controller.busy)
    transaction = controller.session.transactions[-1]
    assert transaction["actual_iq"] == []
    assert transaction["comparison"]["exact"] and transaction["comparison"]["not_requested"]
    assert transaction["verification"]["META"] == 1
    cleanup(controller)


def test_stop_drains_worker_and_reset_does_not_mix_sessions(qapp):
    controller = ExperimentController()
    connect_replay(controller)
    finished, beats = [], []
    controller.finished.connect(finished.append)
    timer = QTimer()
    timer.setInterval(3)
    timer.timeout.connect(lambda: beats.append(True))
    timer.start()
    assert controller.run("TX", [(1, 2)] * 4, rounds=100, config=ProfileConfig(samples=4))
    QTimer.singleShot(60, controller.stop)
    until(lambda: not controller.busy)
    timer.stop()
    assert beats and finished[-1]["stopped"]
    assert controller.session.state == "STOPPED"
    assert 0 < len(controller.session.transactions) < 100
    assert controller.state == "READY"
    old_id = controller.session.id
    assert not controller.reset()
    assert controller.disconnect()
    until(lambda: not controller.busy)
    assert controller.reset()
    assert controller.session.id != old_id and not controller.session.transactions
    cleanup(controller)


def test_legacy_replay_fixed_profile_and_pending_rx(qapp):
    controller = ExperimentController()
    connect_replay(controller, version=3)
    assert controller.run("TX", legacy_iq(0), config=ProfileConfig())
    until(lambda: not controller.busy)
    assert controller.state == "WAITING_RX"
    pair_id = controller.session.id
    assert controller.run("RX", [])
    until(lambda: not controller.busy)
    assert controller.state == "READY"
    assert controller.session.id == pair_id and len(controller.session.transactions) == 2
    assert controller.run("TX", [(0, 0)] * 256)
    until(lambda: not controller.busy)
    assert controller.session.state == "FAILED"
    assert controller.session.errors
    cleanup(controller)


def test_new_run_has_independent_evidence_but_same_live_udp_socket(qapp):
    from dashboard.tests.test_stage_d_client import BoardSimulator
    from dashboard.app.experiment.client import HEADER, MAGIC
    board = BoardSimulator(version=4)
    controller = ExperimentController()
    try:
        assert controller.connect_board({"board": "127.0.0.1", "local_ip": "127.0.0.1", "port": board.port, "timeout": .5}, "LIVE")
        until(lambda: not controller.busy)
        assert controller.connected
        assert controller.initialize_utc(1700000000)
        until(lambda: not controller.busy)
        assert controller.run("TX", [(1, -1)] * 4, config=ProfileConfig(samples=4))
        until(lambda: not controller.busy)
        first_id = controller.session.id
        sock = controller._client.sock
        wire_id = controller._client.session_id
        assert len(controller.session.transactions) == 1
        assert controller.run("TX", [(1, -1)] * 4, config=ProfileConfig(samples=4))
        until(lambda: not controller.busy)
        assert controller.session.id != first_id
        assert len(controller.session.transactions) == 1
        assert controller._client.sock is sock and controller._client.session_id == wire_id
        assert controller.session.transactions[0]["packets"][-1]["parsed"]["sequence"] == 1
        assert len(set(board.peers)) == 1
        assert {HEADER.unpack_from(raw)[4] for raw in board.requests if raw.startswith(MAGIC)} == {wire_id}
    finally:
        cleanup(controller)
        board.close()


def test_disconnect_preserves_completed_measurement_export(qapp, tmp_path):
    controller = ExperimentController()
    connect_replay(controller)
    assert controller.run("TX", [(1, -1)] * 4, config=ProfileConfig(samples=4))
    until(lambda: not controller.busy)
    assert controller.session.state == "COMPLETED"
    assert controller.disconnect()
    until(lambda: not controller.busy)
    assert controller.state == "DISCONNECTED" and not controller.connected
    assert controller.session.state == "COMPLETED"
    future = controller.export(tmp_path)
    until(future.done)
    paths = future.result()
    assert "REPLAY FIXTURE PASS" in json.loads(paths["json"].read_text(encoding="utf-8"))["classification"]
    cleanup(controller)


def test_auto_cycle_manages_rx_sequence_without_changing_tx_capture(qapp):
    controller = ExperimentController()
    connect_replay(controller)
    config = ProfileConfig(samples=4)
    assert controller.run("RX", [], packet=build_packet("VERSION", config, sequence=0), config=config)
    until(lambda: not controller.busy)
    assert controller.snapshot()["status"]["RX_VERSION_NEXT"] == 1
    assert controller.run("TX", [(1, -1)] * 4, alternate=True, config=config)
    until(lambda: not controller.busy)
    assert controller.session.state == "COMPLETED"
    tx, rx_version = controller.session.transactions[:2]
    assert tx["packets"][0]["parsed"]["sequence"] == 0
    assert rx_version["packets"][0]["parsed"]["sequence"] == 1
    assert tx["packets"][0]["raw"][4:] == rx_version["packets"][0]["raw"][4:]
    assert "RX sequence managed independently" in rx_version["reference_basis"]
    cleanup(controller)
