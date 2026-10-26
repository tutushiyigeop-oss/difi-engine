"""Windows entry point: python dashboard/main.py (never starts hardware on launch)."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def main() -> int:
    parser = argparse.ArgumentParser(description="DIFI ENGINE CONTROL CENTER")
    parser.add_argument("--smoke-test", action="store_true", help="Open Qt, render, and close without network")
    parser.add_argument("--mode", choices=("B5", "B6", "STAGED"), default="STAGED", help="Select initial workspace; no automatic network connection")
    parser.add_argument("--replay", choices=("B5", "B6", "STAGED"), help="Automatically run clearly marked offline fixture")
    parser.add_argument("--screenshot", type=Path, help="Save window image; with --smoke-test saves before closing")
    parser.add_argument("--page", choices=("overview", "packet", "iq", "waveform", "timeline", "logs", "export"), default="overview", help="Initial Stage D page")
    args = parser.parse_args()
    if sys.version_info < (3, 11):
        parser.error("Python 3.11 or newer is required")
    try:
        from PySide6.QtCore import QTimer
        from PySide6.QtWidgets import QApplication
        from dashboard.app.main_window import MainWindow
        from dashboard.app.theme import apply_theme
    except ImportError as exc:
        print(f"Missing dashboard dependency: {exc}\nRun: python -m pip install -r dashboard/requirements.txt", file=sys.stderr)
        return 2

    app = QApplication(sys.argv[:1])
    app.setApplicationName("DIFI ENGINE CONTROL CENTER")
    app.setOrganizationName("DIFI Project")
    apply_theme(app)
    window = MainWindow()
    initial_mode = args.replay or args.mode
    window.mode_combo.setCurrentIndex({"B5": 0, "B6": 1, "STAGED": 2}[initial_mode])
    if initial_mode == "STAGED":
        window.stage_d.tabs.setCurrentIndex(("overview", "packet", "iq", "waveform", "timeline", "logs", "export").index(args.page))
    screen = app.primaryScreen()
    if screen is not None:
        available = screen.availableGeometry()
        window.resize(min(1740, max(1100, available.width() - 60)),
                      min(970, max(650, available.height() - 70)))
    window.show()
    if args.replay:
        QTimer.singleShot(250, window.start_demo)
    if args.screenshot:
        def capture():
            args.screenshot.parent.mkdir(parents=True, exist_ok=True)
            window.grab().save(str(args.screenshot))
        QTimer.singleShot(7000 if args.replay else 900, capture)
    if args.smoke_test:
        def finish_smoke():
            expected = "COMPLETED" if args.replay else "IDLE"
            if window.mode == "STAGED":
                state = window.stage_d.controller.session.state
                expected = "COMPLETED" if args.replay else "DISCONNECTED"
                passed = state == expected and window.source == "REPLAY"
                transactions = window.stage_d.controller.session.transactions
                packets = sum(len(record.get("packets", [])) for record in transactions)
                iq = sum(len(record.get("actual_iq", [])) for record in transactions)
            else:
                state, packets, iq = window.session.state, window.session.total_packets, window.session.verified_iq
                passed = state == expected and window.source == "REPLAY"
            print(f"SMOKE {'PASS' if passed else 'FAIL'}: Qt={app.platformName()} "
                  f"source={window.source} mode={window.mode} state={state} "
                  f"packets={packets} IQ={iq}", flush=True)
            window.close()
            app.exit(0 if passed else 3)
        QTimer.singleShot(7600 if args.replay else 1400, finish_smoke)
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
