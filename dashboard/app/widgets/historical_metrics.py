"""Archived report references, deliberately independent of live session state."""
from pathlib import Path
from PySide6.QtCore import QUrl
from PySide6.QtGui import QDesktopServices
from PySide6.QtWidgets import QGridLayout, QHBoxLayout, QPushButton
from .common import Card, divider, label
from ..theme import COLORS


class HistoricalMetrics(Card):
    def __init__(self, parent=None):
        super().__init__("HISTORICAL METRICS", parent=parent)
        self.root = Path(__file__).resolve().parents[3]
        self.badge.setText("ARCHIVED RESULT")
        self.badge.setStyleSheet("color:#e9b85f; font-size:9px;")
        grid = QGridLayout()
        grid.setHorizontalSpacing(11)
        grid.setVerticalSpacing(7)
        for row, (value, title) in enumerate((("196.916", "RTL ideal IQ loopback"), ("107.18", "Board DMA transaction window"), ("25.01", "Board full software window"))):
            number = label(value)
            number.setStyleSheet("font:600 22px Consolas; color:#c5d8e9;")
            grid.addWidget(number, row, 0)
            text = label(f"MB/s  ·  {title}", "CardSubtitle")
            text.setWordWrap(True)
            grid.addWidget(text, row, 1)
        grid.setColumnStretch(1, 1)
        self.body.addLayout(grid)
        note = label("Different measurement windows; these are not current UDP throughput measurements.", "CardSubtitle")
        note.setWordWrap(True)
        self.body.addWidget(note)
        self.body.addWidget(divider())
        for title, wns, target in (("Packaged IP", "+0.411", "packaged_ip"), ("B5", "+2.206", "b5_raw_export"), ("B6", "+2.372", "b6_udp_rx")):
            row = QHBoxLayout()
            build = label(f"{title} Rebuild PASS")
            build.setStyleSheet(f"color:{COLORS['success']}; font-size:10px;")
            row.addWidget(build, 1)
            row.addWidget(label(f"WNS {wns} ns", "CardSubtitle"))
            button = QPushButton("↗")
            button.setFixedSize(25, 22)
            button.setStyleSheet("padding:0; color:#8195ae; border:1px solid #263b53;")
            path = self.root / "report/results/vivado_rebuild" / target / "SUCCESS.txt"
            button.setToolTip(str(path))
            button.clicked.connect(lambda checked=False, p=path: self._open(p))
            row.addWidget(button)
            self.body.addLayout(row)
        links = QHBoxLayout()
        for title, relative in (("Performance evidence ↗", "report/results/perf/performance_summary.md"), ("B6 board record ↗", "report/results/vivado_rebuild/b6_udp_rx/BOARD_REGRESSION_STATUS.md")):
            button = QPushButton(title)
            button.setStyleSheet("border:none; background:transparent; color:#7ca8c4; padding:3px 0; font-size:10px;")
            button.clicked.connect(lambda checked=False, p=self.root / relative: self._open(p))
            links.addWidget(button)
        self.body.addLayout(links)

    @staticmethod
    def _open(path):
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(path)))
