"""Signed I16/Q16 sample display with explicit capture/reference provenance."""
import pyqtgraph as pg
from PySide6.QtCore import Qt
from PySide6.QtWidgets import QCheckBox, QHBoxLayout, QSizePolicy
from .common import Card, label
from ..theme import COLORS


class IQWaveform(Card):
    def __init__(self, parent=None):
        super().__init__("I / Q WAVEFORM", parent=parent)
        self.setMinimumHeight(178)
        self.i_samples = []
        self.q_samples = []
        self.source = ""
        self.i_toggle = QCheckBox("I")
        self.q_toggle = QCheckBox("Q")
        self.i_toggle.setChecked(True)
        self.q_toggle.setChecked(True)
        self.i_toggle.setStyleSheet(f"color:{COLORS['DATA']};")
        self.q_toggle.setStyleSheet(f"color:{COLORS['CONTEXT']};")
        self.heading.insertWidget(1, self.i_toggle)
        self.heading.insertWidget(2, self.q_toggle)
        self.badge.setText("NO SAMPLES")
        self.plot = pg.PlotWidget(background="#0b1727")
        self.plot.setMinimumHeight(105)
        # PlotWidget's desktop default hint is 600×450. Ignore its preferred
        # vertical size so the dashboard can fit its plot into a compact card.
        self.plot.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Ignored)
        self.plot.setMenuEnabled(False)
        self.plot.showGrid(x=True, y=True, alpha=.13)
        self.plot.setLabel("left", "Signed I16 / Q16", color=COLORS["muted"], size="9pt")
        self.plot.setLabel("bottom", "Sample index", color=COLORS["muted"], size="9pt")
        self.plot.setMouseEnabled(x=True, y=True)
        for name in ("left", "bottom"):
            self.plot.getAxis(name).setPen(pg.mkPen("#38516a"))
            self.plot.getAxis(name).setTextPen(pg.mkPen("#8195ae"))
        self.i_curve = self.plot.plot([], [], pen=pg.mkPen(COLORS["DATA"], width=1.4), name="I", autoDownsample=True, clipToView=True)
        self.q_curve = self.plot.plot([], [], pen=pg.mkPen(COLORS["CONTEXT"], width=1.4), name="Q", autoDownsample=True, clipToView=True)
        self.crosshair = pg.InfiniteLine(angle=90, movable=False, pen=pg.mkPen("#6f879f", width=1, style=Qt.PenStyle.DotLine))
        self.plot.addItem(self.crosshair, ignoreBounds=True)
        self.crosshair.hide()
        self.empty_text = pg.TextItem("Awaiting samples with a known source", color=COLORS["muted"], anchor=(.5, .5))
        self.plot.addItem(self.empty_text)
        self.plot.setRange(xRange=(0, 256), yRange=(-32768, 32767), padding=0)
        self.empty_text.setPos(128, 0)
        self.body.addWidget(self.plot, 1)
        footer = QHBoxLayout()
        self.provenance = label("No sample source available", "CardSubtitle")
        self.provenance.setWordWrap(True)
        footer.addWidget(self.provenance, 1)
        self.hover_value = label("sample —  I —  Q —", "CardSubtitle")
        self.hover_value.setStyleSheet("font:10px Consolas; color:#a8bdd3;")
        footer.addWidget(self.hover_value)
        self.body.addLayout(footer)
        self.i_toggle.toggled.connect(self.i_curve.setVisible)
        self.q_toggle.toggled.connect(self.q_curve.setVisible)
        self.mouse_proxy = pg.SignalProxy(self.plot.scene().sigMouseMoved, rateLimit=30, slot=self._hover)

    def set_samples(self, i, q, source):
        if not len(i) or not len(q):
            self.clear()
            return
        count = min(len(i), len(q))
        self.i_samples = [int(value) for value in i[:count]]
        self.q_samples = [int(value) for value in q[:count]]
        self.source = str(source)
        x = range(count)
        self.i_curve.setData(list(x), self.i_samples)
        self.q_curve.setData(list(range(count)), self.q_samples)
        self.empty_text.hide()
        self.plot.enableAutoRange()
        self.badge.setText(f"{count:,} SAMPLES")
        self.provenance.setText(self.source)
        reference = "golden" in self.source.lower() or "reference" in self.source.lower()
        self.provenance.setStyleSheet(f"color:{COLORS['CONTEXT'] if reference else COLORS['DATA']}; font-size:10px;")

    def clear(self):
        self.i_samples = []
        self.q_samples = []
        self.source = ""
        self.i_curve.setData([], [])
        self.q_curve.setData([], [])
        self.crosshair.hide()
        self.badge.setText("NO SAMPLES")
        self.provenance.setText("No sample source available")
        self.provenance.setStyleSheet(f"color:{COLORS['muted']}; font-size:10px;")
        self.hover_value.setText("sample —  I —  Q —")
        self.empty_text.show()
        self.plot.setRange(xRange=(0, 256), yRange=(-32768, 32767), padding=0)
        self.empty_text.setPos(128, 0)

    def _hover(self, event):
        position = event[0]
        if not self.i_samples or not self.plot.sceneBoundingRect().contains(position):
            self.crosshair.hide()
            return
        point = self.plot.getViewBox().mapSceneToView(position)
        index = round(point.x())
        if 0 <= index < len(self.i_samples):
            self.crosshair.setPos(index)
            self.crosshair.show()
            self.hover_value.setText(f"sample {index:,}  I {self.i_samples[index]:+d}  Q {self.q_samples[index]:+d}")
        else:
            self.crosshair.hide()
