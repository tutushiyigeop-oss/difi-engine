"""Instrument palette and native Qt styling for the control center."""
from PySide6.QtGui import QColor, QFont, QPalette

COLORS = {
    "background": "#09111e", "panel": "#101d2e", "panel_alt": "#142337",
    "text": "#e2edf8", "muted": "#8195ae", "border": "#263b53",
    "VERSION": "#ae9aff", "CONTEXT": "#e9b85f", "DATA": "#54d3ed",
    "success": "#57d9aa", "warning": "#e9b85f", "error": "#fa7c87",
    "cyan": "#54d3ed", "green": "#57d9aa", "purple": "#ae9aff",
}

STYLESHEET = """
QWidget { color: #e2edf8; font-family: 'Segoe UI'; font-size: 12px; }
QMainWindow, QDialog { background: #09111e; }
QWidget#centralWidget, QScrollArea, QScrollArea > QWidget > QWidget { background: #09111e; }
QFrame#Card, QWidget#Card { background: #101d2e; border: 1px solid #263b53; border-radius: 10px; }
QLabel { background: transparent; border: none; }
QLabel#CardTitle { color: #a8bdd3; font-size: 10px; font-weight: 700; letter-spacing: 1.5px; }
QLabel#CardSubtitle { color: #8195ae; font-size: 10px; }
QLabel#MetricValue { font-family: Consolas; font-size: 28px; font-weight: 600; }
QLabel#MetricLabel { color: #8195ae; font-size: 10px; }
QLabel#AppTitle { font-size: 23px; font-weight: 700; letter-spacing: 1px; }
QLabel#AppSubtitle { color: #8195ae; font-size: 11px; letter-spacing: .4px; }
QLabel#eyebrow { color: #5c8caa; font-family: Consolas; font-size: 10px; letter-spacing: 1.8px; }
QLabel#preflight { color: #94b0c7; background: #102335; border: 1px solid #24435a; border-left: 3px solid #388da5; border-radius: 5px; padding: 8px 12px; font-size: 11px; }
QLabel#endpoint { color: #9ab0c6; font: 11px Consolas; }
QLabel#footnote { color: #69829d; font-size: 10px; }
QLabel#sourceBadge { color: #e9b85f; background: #332b20; border: 1px solid #6b5630; border-radius: 5px; padding: 8px 12px; max-height:18px; font-size: 10px; font-weight: 700; letter-spacing: 1px; }
QLabel#stateBadge { color: #8195ae; padding: 8px 9px; max-height:18px; font: 600 12px Consolas; }
QPushButton, QToolButton { background: #182c42; border: 1px solid #2c4660; border-radius: 5px; padding: 7px 13px; font-weight: 600; }
QPushButton:hover, QToolButton:hover { background: #223e56; border-color: #54d3ed; }
QPushButton:pressed, QToolButton:pressed { background: #2a5164; }
QPushButton:checked { background: #173f50; border-color: #54d3ed; color: #74e4f5; }
QPushButton:disabled, QToolButton:disabled { color: #50647c; background: #112033; border-color: #1c3047; }
QPushButton#PrimaryButton { background: #0e7188; border: 1px solid #33b5cf; color: #f1fcff; }
QPushButton#PrimaryButton:hover { background: #10859b; }
QPushButton#PrimaryButton:disabled { background: #173443; color: #63808f; border-color: #284658; }
QPushButton#DangerButton { color: #fa9ea5; border-color: #643d4b; }
QComboBox, QLineEdit, QSpinBox, QDoubleSpinBox { background: #0b1727; border: 1px solid #2a405a; border-radius: 5px; padding: 6px 8px; selection-background-color: #245e76; }
QComboBox:focus, QLineEdit:focus, QSpinBox:focus, QDoubleSpinBox:focus { border-color: #54d3ed; }
QComboBox::drop-down { border: none; width: 22px; }
QComboBox QAbstractItemView { background: #142337; border: 1px solid #2a405a; selection-background-color: #245e76; }
QTextEdit, QPlainTextEdit, QListWidget, QTreeWidget, QTableWidget { background: #0b1727; border: 1px solid #22364e; border-radius: 5px; selection-background-color: #245e76; }
QCheckBox { color: #a8bdd3; spacing: 5px; }
QCheckBox::indicator { width: 12px; height: 12px; border: 1px solid #405b76; border-radius: 3px; background: #0b1727; }
QCheckBox::indicator:checked { background: #38b2ca; border-color: #74dcec; }
QProgressBar { background: #0b1727; border: none; border-radius: 3px; height: 5px; text-align: center; }
QProgressBar::chunk { background: #54d3ed; border-radius: 3px; }
QScrollBar:vertical { background: transparent; width: 7px; margin: 2px; }
QScrollBar::handle:vertical { background: #304a64; border-radius: 2px; min-height: 24px; }
QScrollBar:horizontal { background: transparent; height: 7px; margin: 2px; }
QScrollBar::handle:horizontal { background: #304a64; border-radius: 2px; min-width: 24px; }
QScrollBar::add-line, QScrollBar::sub-line { width: 0px; height: 0px; }
QScrollBar::add-page, QScrollBar::sub-page { background: none; }
QTabWidget::pane { border: 1px solid #263b53; background: #101d2e; border-radius: 6px; }
QTabBar::tab { background: #101d2e; color: #8195ae; border: none; padding: 9px 15px; }
QTabBar::tab:selected { color: #54d3ed; border-bottom: 2px solid #54d3ed; }
QGroupBox { border: 1px solid #263b53; border-radius: 7px; margin-top: 10px; padding-top: 13px; }
QGroupBox::title { subcontrol-origin: margin; left: 12px; padding: 0px 5px; color: #a8bdd3; }
QToolTip { background: #1b3046; border: 1px solid #405d79; color: #e2edf8; padding: 5px; }
QStatusBar { background: #0b1727; color: #8195ae; border-top: 1px solid #263b53; }
QMenu { background: #142337; border: 1px solid #2a405a; }
QMenu::item:selected { background: #245e76; }
QSplitter::handle { background: #09111e; }
"""
stylesheet = STYLESHEET


def apply_theme(app):
    app.setStyle("Fusion")
    app.setFont(QFont("Segoe UI", 10))
    palette = QPalette()
    palette.setColor(QPalette.ColorRole.Window, QColor(COLORS["background"]))
    palette.setColor(QPalette.ColorRole.WindowText, QColor(COLORS["text"]))
    palette.setColor(QPalette.ColorRole.Base, QColor("#0b1727"))
    palette.setColor(QPalette.ColorRole.AlternateBase, QColor(COLORS["panel"]))
    palette.setColor(QPalette.ColorRole.Text, QColor(COLORS["text"]))
    palette.setColor(QPalette.ColorRole.Button, QColor("#182c42"))
    palette.setColor(QPalette.ColorRole.ButtonText, QColor(COLORS["text"]))
    palette.setColor(QPalette.ColorRole.Highlight, QColor("#245e76"))
    palette.setColor(QPalette.ColorRole.HighlightedText, QColor("#ffffff"))
    app.setPalette(palette)
    app.setStyleSheet(STYLESHEET)
