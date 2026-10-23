"""Bounded native log view retaining the complete underlying event log."""
from datetime import datetime
from PySide6.QtGui import QColor, QFont, QTextCharFormat, QTextCursor
from PySide6.QtWidgets import QApplication, QCheckBox, QComboBox, QFileDialog, QHBoxLayout, QMessageBox, QPushButton, QTextEdit
from .common import Card
from ..theme import COLORS


class LogConsole(Card):
    VISUAL_LIMIT = 1500

    def __init__(self, parent=None):
        super().__init__("EVENT CONSOLE", parent=parent)
        self.logs = []
        self.filter = QComboBox()
        self.filter.addItems(["ALL", "INFO", "PASS", "WARN", "FAIL", "ERROR"])
        self.filter.setFixedWidth(74)
        self.follow = QCheckBox("Follow")
        self.follow.setChecked(True)
        tools = QHBoxLayout()
        tools.setSpacing(5)
        tools.addWidget(self.filter)
        tools.addWidget(self.follow)
        tools.addStretch(1)
        for title, action in (("Copy", self.copy), ("Clear", self.clear), ("Export", self.export)):
            button = QPushButton(title)
            button.setStyleSheet("padding:5px 5px; font-size:10px;")
            button.clicked.connect(action)
            tools.addWidget(button)
        self.body.addLayout(tools)
        self.editor = QTextEdit()
        self.editor.setReadOnly(True)
        self.editor.setAcceptRichText(False)
        self.editor.setFont(QFont("Consolas", 9))
        self.editor.setStyleSheet("background:#0a1524; border:1px solid #1d3148; padding:8px; font-family:Consolas; font-size:11px;")
        self.editor.document().setMaximumBlockCount(self.VISUAL_LIMIT)
        self.editor.setPlaceholderText("Awaiting session events…\n\nLive tool output and explicitly marked replay events appear here.")
        self.body.addWidget(self.editor, 1)
        self.filter.currentTextChanged.connect(self._rebuild)
        self.follow.toggled.connect(self._follow_changed)
        self.badge.setText("0 ENTRIES")
        self.level_colors = {"INFO": "#90a6bd", "PASS": COLORS["success"], "WARN": COLORS["warning"], "FAIL": COLORS["error"], "ERROR": COLORS["error"]}

    @staticmethod
    def format_log(entry):
        return f"{entry['timestamp']}  {entry['level']:<5}  {entry['source']}  {entry['message']}"

    def append(self, level, source, message, timestamp=None):
        stamp = timestamp.isoformat(timespec="milliseconds") if isinstance(timestamp, datetime) else str(timestamp or datetime.now().astimezone().isoformat(timespec="milliseconds"))
        entry = {"timestamp": stamp, "level": str(level).upper(), "source": str(source), "message": str(message)}
        self.logs.append(entry)
        self.badge.setText(f"{len(self.logs):,} ENTRIES")
        if self.filter.currentIndex() == 0 or self.filter.currentText() == entry["level"]:
            self._insert(entry)

    def _insert(self, entry):
        scrollbar = self.editor.verticalScrollBar()
        previous = scrollbar.value()
        cursor = QTextCursor(self.editor.document())
        cursor.movePosition(QTextCursor.MoveOperation.End)
        if not self.editor.document().isEmpty():
            cursor.insertBlock()
        fmt = QTextCharFormat()
        fmt.setForeground(QColor("#607991"))
        cursor.insertText(entry["timestamp"][11:23] if "T" in entry["timestamp"] else entry["timestamp"], fmt)
        fmt.setForeground(QColor(self.level_colors.get(entry["level"], "#90a6bd")))
        cursor.insertText(f"  {entry['level']:<5} ", fmt)
        fmt.setForeground(QColor("#6d8ca8"))
        cursor.insertText(f"[{entry['source']}]\n", fmt)
        fmt.setForeground(QColor(self.level_colors.get(entry["level"], "#bbcddd")))
        cursor.insertText(entry["message"], fmt)
        scrollbar.setValue(scrollbar.maximum() if self.follow.isChecked() else previous)

    def _rebuild(self, *_):
        self.editor.clear()
        level = self.filter.currentText()
        entries = self.logs if self.filter.currentIndex() == 0 else [entry for entry in self.logs if entry["level"] == level]
        for entry in entries[-self.VISUAL_LIMIT // 3:]:
            self._insert(entry)

    def _follow_changed(self, follow):
        if follow:
            self.editor.verticalScrollBar().setValue(self.editor.verticalScrollBar().maximum())

    def clear(self):
        self.logs.clear()
        self.editor.clear()
        self.badge.setText("0 ENTRIES")

    def copy(self):
        if self.editor.textCursor().hasSelection():
            self.editor.copy()
        else:
            level = self.filter.currentText()
            QApplication.clipboard().setText("\n".join(self.format_log(entry) for entry in self.logs if self.filter.currentIndex() == 0 or entry["level"] == level))

    def export(self):
        path, _ = QFileDialog.getSaveFileName(self, "Export raw event log", "difi_event_log.txt", "Text files (*.txt)")
        if path:
            try:
                with open(path, "w", encoding="utf-8", newline="\n") as stream:
                    stream.write("\n".join(self.format_log(entry) for entry in self.logs) + "\n")
            except OSError as exc:
                QMessageBox.warning(self, "Log export failed", str(exc))
