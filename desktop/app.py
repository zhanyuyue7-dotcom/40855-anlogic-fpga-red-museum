from __future__ import annotations

import argparse
from collections import deque
from datetime import datetime
import json
from pathlib import Path
import socket
import sys
import threading
import time
import traceback

import serial
from serial.tools import list_ports
from PyQt5.QtCore import Qt, QThread, QTimer, pyqtSignal, QSettings
from PyQt5.QtGui import QColor, QFont, QIcon, QPainter, QPainterPath, QPen, QPixmap
from PyQt5.QtWidgets import (
    QApplication, QComboBox, QFileDialog, QFormLayout, QFrame, QGridLayout,
    QHBoxLayout, QHeaderView, QLabel, QLineEdit, QMainWindow, QMessageBox,
    QPlainTextEdit, QProgressBar, QPushButton, QScrollArea, QSpinBox,
    QSizePolicy, QSplitter, QTabWidget, QTableWidget, QTableWidgetItem, QVBoxLayout, QWidget,
)

from core import (ImageReceiver, SessionStore, TelemetryDecoder, TransferCancelled,
                  command_packet, data_directory, endpoint, prepare_image, timestamp, upload_image)


STYLE = """
QWidget { background: #081426; color: #e6eefb; font-family: 'Microsoft YaHei UI'; font-size: 13px; }
QMainWindow { background: #081426; }
QFrame#card { background: #10223b; border: 1px solid #233d5c; border-radius: 12px; }
QFrame#card QLabel, QFrame#card QWidget#transparent { background: transparent; border: none; }
QLabel#title { font-size: 27px; font-weight: 700; }
QLabel#subtitle, QLabel#muted { color: #9db3d0; }
QLabel#section { font-size: 16px; font-weight: 600; }
QLabel#metric { color: #60d9f1; font-size: 27px; font-weight: 700; }
QLabel#badge { background: #183450; color: #99d9ff; border-radius: 12px; padding: 7px 14px; }
QPushButton { background: #183553; border: 1px solid #355675; border-radius: 7px; padding: 10px 15px; min-height: 19px; font-weight: 600; }
QPushButton:hover { background: #254d72; border-color: #65bdf4; }
QPushButton:pressed { background: #103b67; }
QPushButton:focus { border: 2px solid #7fd7ff; }
QPushButton#primary { background: #1574db; border-color: #388ee8; color: white; }
QPushButton#primary:hover { background: #2486ed; }
QPushButton#stop { background: #442b43; border-color: #965775; color: #ffcfdf; }
QPushButton:disabled, QPushButton#primary:disabled, QPushButton#stop:disabled { background: #12253b; border-color: #263c54; color: #74879f; }
QLineEdit, QComboBox, QSpinBox { background: #0b192d; border: 1px solid #36516e; border-radius: 6px; padding: 7px; min-height: 20px; selection-background-color: #226bb0; }
QLineEdit:focus, QComboBox:focus, QSpinBox:focus { border-color: #6bcbff; }
QComboBox QAbstractItemView { background: #152c46; color: #e6eefb; selection-background-color: #265e92; }
QTabWidget::pane { border: 1px solid #243d59; border-radius: 8px; }
QTabBar::tab { background: #10223b; color: #afc3db; padding: 11px 22px; border-bottom: 2px solid #10223b; }
QTabBar::tab:selected { color: #69d4ff; border-bottom-color: #35a9f5; background: #17324f; }
QTableWidget { background: #0b192c; alternate-background-color: #10233b; gridline-color: #213951; border: none; selection-background-color: #22517b; selection-color: #ffffff; }
QHeaderView::section { background: #16304d; color: #b6cde7; border: none; border-bottom: 1px solid #31506e; padding: 10px; }
QPlainTextEdit { background: #09172a; border: 1px solid #233d5c; border-radius: 7px; padding: 8px; font-family: Consolas, 'Microsoft YaHei UI'; }
QProgressBar { background: #0a192d; border: 1px solid #294967; border-radius: 5px; text-align: center; min-height: 20px; }
QProgressBar::chunk { background: #197fca; border-radius: 4px; }
QScrollArea { border: none; }
QScrollBar:vertical { background: #102039; width: 10px; }
QScrollBar::handle:vertical { background: #355679; min-height: 24px; border-radius: 5px; }
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height: 0; }
QSplitter::handle { background: #081426; }
QToolTip { background: #204366; color: white; border: 1px solid #78c8ff; padding: 5px; }
"""


class CaptureWorker(QThread):
    batch = pyqtSignal(object, object)
    status = pyqtSignal(str)
    failed = pyqtSignal(str)

    def __init__(self, port, baud, mode, store, parent=None):
        super().__init__(parent)
        self.port, self.baud, self.mode, self.store = port, baud, mode, store
        self.stop_event = threading.Event()

    def run(self):
        decoder = TelemetryDecoder(self.mode)
        received = count = 0
        pending = []
        last = time.monotonic()
        try:
            # Explicit 8N1, no flow control, no application TX commands.
            with serial.serial_for_url(self.port, baudrate=self.baud, timeout=0.08,
                                       bytesize=8, parity="N", stopbits=1,
                                       xonxoff=False, rtscts=False, dsrdtr=False) as device:
                self.status.emit("串口已打开 · 等待数据")
                with self.store.path.with_suffix(".raw.bin").open("ab") as raw:
                    while not self.stop_event.is_set():
                        data = device.read(min(max(device.in_waiting, 1), 8192))
                        if data:
                            raw.write(data)
                            received += len(data)
                            records = [{"timestamp": timestamp(), **f} for f in decoder.feed(data)]
                            pending.extend(records)
                            count += len(records)
                        if time.monotonic() - last >= 0.1:
                            if pending:
                                self.store.append(pending)
                            self.batch.emit(pending[-300:], {"bytes": received, "count": count, "invalid": decoder.invalid})
                            pending = []
                            raw.flush()
                            last = time.monotonic()
                    if pending:
                        self.store.append(pending)
                        self.batch.emit(pending[-300:], {"bytes": received, "count": count, "invalid": decoder.invalid})
        except Exception as exc:
            if pending:
                try:
                    self.store.append(pending)
                    self.batch.emit(pending[-300:], {"bytes": received, "count": count, "invalid": decoder.invalid})
                except Exception as save_error:
                    self.failed.emit("最后一批记录未能保存：" + str(save_error))
            self.failed.emit(str(exc))


class UploadWorker(QThread):
    progress = pyqtSignal(int, int)
    result = pyqtSignal(bool, str)
    stage = pyqtSignal(str)

    def __init__(self, host, port, data, name, parent=None, fpga=False, commit_timeout=3.0):
        super().__init__(parent)
        self.args = host, port, data, name
        self.stop_event = threading.Event()
        self.is_fpga = fpga
        self.commit_timeout = commit_timeout

    def run(self):
        try:
            if self.is_fpga:
                from fpga_transfer import upload_to_fpga
                receipt = upload_to_fpga(*self.args, progress=self.progress.emit, cancel=self.stop_event,
                                         stage=self.stage.emit, commit_timeout=self.commit_timeout)
                self.result.emit(True, f"设备已确认显示提交；CRC32={receipt['image_crc32']}；重传{receipt['retransmissions']}次；记录：{receipt['receipt_path']}")
                return
            digest = upload_image(*self.args, progress=self.progress.emit, cancel=self.stop_event)
            self.result.emit(True, "接收端已确认完整照片，SHA-256: " + digest)
        except (Exception, TransferCancelled) as exc:
            self.result.emit(False, str(exc))


class DeviceProbeWorker(QThread):
    result = pyqtSignal(bool, str)

    def __init__(self, host, port, parent=None):
        super().__init__(parent)
        self.host, self.port = host, port
        self.stop_event = threading.Event()

    def run(self):
        from fpga_transfer import probe_device
        try:
            info = probe_device(self.host, self.port, self.stop_event)
            self.result.emit(True, f"设备支持HXFP：{info.width}×{info.height} RGB565，每包至多{info.max_chunk}B；状态{info.phase}")
        except Exception as exc:
            self.result.emit(False, str(exc))


class ExportWorker(QThread):
    result = pyqtSignal(bool, str)

    def __init__(self, store, path, parent=None):
        super().__init__(parent)
        self.store, self.path = store, path

    def run(self):
        try:
            count = self.store.export_csv(self.path)
            self.result.emit(True, f"已导出 {count:,} 条记录 → {self.path}")
        except Exception as exc:
            self.result.emit(False, "导出失败：" + str(exc))


class TrafficPlot(QWidget):
    def __init__(self):
        super().__init__()
        self.values = deque([0.0] * 60, maxlen=60)
        self.setMinimumHeight(92)
        self.setAccessibleName("串口接收速率，最近 60 秒，单位字节每秒")

    def paintEvent(self, _):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.fillRect(self.rect(), QColor("#10223b"))
        w, h = self.width() - 10, self.height() - 26
        painter.setPen(QPen(QColor("#25405e"), 1))
        for ratio in (0, 0.5, 1):
            y = int(8 + ratio * h)
            painter.drawLine(5, y, int(w), y)
        ceiling = max(100, max(self.values) * 1.2)
        path = QPainterPath()
        for i, value in enumerate(self.values):
            x, y = 5 + i * (w - 5) / 59, 8 + h * (1 - value / ceiling)
            path.moveTo(x, y) if i == 0 else path.lineTo(x, y)
        painter.setPen(QPen(QColor("#48d9ec"), 2))
        painter.drawPath(path)
        painter.setPen(QColor("#a4bcd6"))
        painter.drawText(7, self.height() - 3, f"RX   {self.values[-1]:,.0f} B/s                  最近 60 秒")


def label(text, name=None):
    item = QLabel(text)
    if name:
        item.setObjectName(name)
    return item


def button(text, slot, name=None):
    item = QPushButton(text)
    item.setCursor(Qt.PointingHandCursor)
    if name:
        item.setObjectName(name)
    item.clicked.connect(slot)
    return item


def card(title=None):
    frame = QFrame()
    frame.setObjectName("card")
    layout = QVBoxLayout(frame)
    layout.setContentsMargins(18, 16, 18, 16)
    layout.setSpacing(12)
    if title:
        layout.addWidget(label(title, "section"))
    return frame, layout


class MainWindow(QMainWindow):
    def __init__(self, settings=None):
        super().__init__()
        self.setWindowTitle("HX4S20 Studio · 以太网与串口工作台")
        self.resize(1380, 940)
        self.setMinimumSize(1060, 760)
        self.settings = settings if settings is not None else QSettings("Shunying", "HX4S20Studio")
        self.capture = self.upload = self.exporter = None
        self.device_probe = None
        self.store = None
        self.image_data = None
        self.image_path = None
        self.sequence = 0
        self.total_bytes = self.old_bytes = self.record_count = 0
        self.last_frame = 0
        self.started = 0
        self._closing = False
        self._capture_error = False
        self.report_dialog = None
        root = QWidget()
        outer = QVBoxLayout(root)
        outer.setContentsMargins(26, 20, 26, 16)
        outer.setSpacing(18)
        self.setCentralWidget(root)

        header = QHBoxLayout()
        titles = QVBoxLayout()
        titles.addWidget(label("HX4S20  /  STUDIO", "title"))
        titles.addWidget(label("瞬影 FPGA 工作台     /     ETHERNET + UART", "subtitle"))
        header.addLayout(titles)
        header.addStretch()
        self.badge = label("待机 · 未采集", "badge")
        header.addWidget(self.badge)
        outer.addLayout(header)

        actions = QHBoxLayout()
        self.start_button = button("▶  开始采集", self.start_capture, "primary")
        self.stop_button = button("■  停止采集", self.stop_capture, "stop")
        self.export_button = button("↓  导出成 CSV", self.export_csv)
        self.stop_button.setEnabled(False)
        self.export_button.setEnabled(False)
        self.start_button.setToolTip("打开选定串口并记录状态，不发送 FPGA 控制命令")
        self.stop_button.setToolTip("停止本机接收并关闭串口，保留已采集数据")
        for b in (self.start_button, self.stop_button, self.export_button):
            actions.addWidget(b)
        actions.addStretch()
        actions.addWidget(button("测试档案 / 历史回放", self.open_report))
        self.elapsed = label("本次采集   00:00:00", "muted")
        actions.addWidget(self.elapsed)
        outer.addLayout(actions)

        metrics = QHBoxLayout()
        self.metrics = {}
        for key, title, value in (("count", "有效记录", "0"), ("bytes", "接收流量", "0 B"),
                                   ("image", "当前图片索引", "—"), ("scene", "设备场景", "等待数据")):
            frame, lay = card()
            lay.addWidget(label(title, "muted"))
            self.metrics[key] = label(value, "metric")
            lay.addWidget(self.metrics[key])
            metrics.addWidget(frame)
        outer.addLayout(metrics)

        split = QSplitter(Qt.Horizontal)
        outer.addWidget(split, 1)
        sidebar_scroll = QScrollArea()
        sidebar_scroll.setWidgetResizable(True)
        sidebar_scroll.setMinimumWidth(320)
        sidebar_scroll.setMaximumWidth(410)
        sidebar = QWidget()
        side = QVBoxLayout(sidebar)
        side.setContentsMargins(0, 0, 10, 0)
        side.setSpacing(14)
        sidebar_scroll.setWidget(sidebar)
        split.addWidget(sidebar_scroll)

        frame, lay = card("01   串口连接")
        form = QFormLayout()
        form.setSpacing(10)
        self.port = QComboBox()
        self.port.setMinimumWidth(160)
        self.port.setToolTip("请根据 USB 串口适配器选择端口；不自动打开蓝牙端口")
        self.baud = QComboBox()
        self.baud.addItems(["9600", "19200", "38400", "57600", "115200", "230400", "460800", "921600"])
        self.baud.setCurrentText(str(self.settings.value("baud", "115200")))
        self.mode = QComboBox()
        self.mode.addItems(["自动识别", "M3 二进制", "Lab4 文本", "原始 HEX"])
        form.addRow("串口", self.port)
        form.addRow("波特率", self.baud)
        form.addRow("解析协议", self.mode)
        lay.addLayout(form)
        self.refresh_button = button("刷新串口列表", self.refresh_ports)
        lay.addWidget(self.refresh_button)
        lay.addWidget(label("8 数据位 · 无校验 · 1 停止位", "muted"))
        side.addWidget(frame)

        frame, lay = card("02   以太网目标")
        form = QFormLayout()
        self.host = QLineEdit(str(self.settings.value("host", "172.22.115.79")))
        self.netport = QSpinBox()
        self.netport.setRange(1, 65535)
        self.netport.setValue(int(self.settings.value("netport", 5000)))
        self.profile = QComboBox()
        self.profile.addItems(["FPGA 旧版控制", "电脑照片接收服务（HXIM）", "FPGA 图片直传（HXFP）"])
        self.profile.setSizeAdjustPolicy(QComboBox.AdjustToMinimumContentsLengthWithIcon)
        self.profile.setMinimumContentsLength(10)
        self.profile.setCurrentIndex(2)
        self.image_port = QSpinBox()
        self.image_port.setRange(1, 65535)
        self.image_port.setValue(int(self.settings.value("image_port", 5002)))
        self.commit_wait = QSpinBox()
        self.commit_wait.setRange(1, 30)
        self.commit_wait.setValue(int(self.settings.value("commit_wait", 3)))
        self.commit_wait.setSuffix(" 秒/次")
        self.commit_wait.setToolTip("显示提交确认的每次等待时间，最多发送6次。像素收齐后仍等待设备确认，确认前保持99%。")
        form.addRow("目标 IPv4", self.host)
        form.addRow("UDP 端口", self.netport)
        form.addRow("FPGA 图片端口", self.image_port)
        form.addRow("显示确认等待", self.commit_wait)
        form.addRow("接收端类型", self.profile)
        lay.addLayout(form)
        self.network_note = label("现有固件：支持控制命令，无 ACK；照片接收尚未实现。", "muted")
        self.network_note.setWordWrap(True)
        lay.addWidget(self.network_note)
        self.probe_button = button("检测设备图片接口", self.probe_fpga)
        lay.addWidget(self.probe_button)
        side.addWidget(frame)

        frame, lay = card("03   FPGA 网络控制")
        grid = QGridLayout()
        self.control_buttons = []
        for i, (text, opcode) in enumerate((("下一张", 0x10), ("轮播开关", 0x11), ("显示提示", 0x12),
                                           ("清除提示", 0x13), ("亮度 +", 0x14), ("亮度 −", 0x15))):
            b = button(text, lambda checked=False, op=opcode, name=text: self.send_command(op, name))
            grid.addWidget(b, i // 2, i % 2)
            self.control_buttons.append(b)
        lay.addLayout(grid)
        lay.addWidget(label("设备状态以 UART 实际回传为准", "muted"))
        side.addWidget(frame)
        side.addStretch()

        content = QWidget()
        right = QVBoxLayout(content)
        right.setContentsMargins(8, 0, 0, 0)
        right.setSpacing(14)
        split.addWidget(content)
        split.setStretchFactor(1, 1)
        top = QHBoxLayout()
        status_frame, status_layout = card("实时状态")
        self.status_fields = {}
        for key, title in (("sd", "SD 初始化"), ("auto", "自动轮播"), ("brightness", "亮度"),
                            ("audio", "音频"), ("fault", "存储故障"), ("invalid", "无效帧")):
            row = QHBoxLayout()
            row.addWidget(label(title, "muted"))
            row.addStretch()
            self.status_fields[key] = label("—")
            row.addWidget(self.status_fields[key])
            status_layout.addLayout(row)
        status_frame.setMinimumWidth(220)
        top.addWidget(status_frame, 1)
        traffic_frame, traffic_layout = card("接收速率")
        self.plot = TrafficPlot()
        traffic_layout.addWidget(self.plot, 1)
        self.status_detail = label("尚无串口数据。选择端口后点击「开始采集」。", "muted")
        self.status_detail.setWordWrap(True)
        traffic_layout.addWidget(self.status_detail)
        top.addWidget(traffic_frame, 2)
        right.addLayout(top)

        self.tabs = QTabWidget()
        right.addWidget(self.tabs, 1)
        photos = QWidget()
        photo_layout = QVBoxLayout(photos)
        photo_layout.setContentsMargins(18, 16, 18, 16)
        photo_row = QHBoxLayout()
        photo_row.addWidget(label("照片传输", "section"))
        photo_row.addStretch()
        self.fit = QComboBox()
        self.fit.addItems(["留边适配", "居中裁剪", "拉伸铺满"])
        photo_row.addWidget(self.fit)
        self.choose_button = button("选择照片…", self.choose_image)
        photo_row.addWidget(self.choose_button)
        photo_layout.addLayout(photo_row)
        self.preview = QLabel("640 × 480\n\n选择 JPG / PNG / BMP / WebP 照片\n自动转换为 24 位 BMP")
        self.preview.setAlignment(Qt.AlignCenter)
        self.preview.setMinimumHeight(155)
        self.preview.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Expanding)
        self.preview.setStyleSheet("background: #0a192c; border: 1px dashed #436385; border-radius: 10px; color: #a6bdd6;")
        photo_layout.addWidget(self.preview, 1)
        self.photo_info = label("未选择照片", "muted")
        self.photo_info.setWordWrap(True)
        photo_layout.addWidget(self.photo_info)
        self.progress = QProgressBar()
        self.progress.setValue(0)
        photo_layout.addWidget(self.progress)
        photo_buttons = QHBoxLayout()
        self.save_image_button = button("另存为 BMP", self.save_bmp)
        self.upload_button = button("通过以太网上传", self.start_upload, "primary")
        self.cancel_button = button("取消传输", self.cancel_upload)
        for b in (self.save_image_button, self.upload_button, self.cancel_button):
            b.setEnabled(False)
            photo_buttons.addWidget(b)
        photo_layout.addLayout(photo_buttons)
        self.transfer_note = label("当前 FPGA 固件仅支持网络控制。上传照片请选择左侧「HXIM 照片接收服务」。", "muted")
        self.transfer_note.setWordWrap(True)
        photo_layout.addWidget(self.transfer_note)
        self.tabs.addTab(photos, "照片上传")

        table_page = QWidget()
        table_layout = QVBoxLayout(table_page)
        table_layout.addWidget(label("显示最近 300 条记录；CSV 包含本次采集的全部记录。", "muted"))
        self.table = QTableWidget(0, 7)
        self.table.setHorizontalHeaderLabels(["时间", "协议", "场景", "图片索引", "轮播", "亮度", "状态 / HEX"])
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.table.setAlternatingRowColors(True)
        self.table.setEditTriggers(QTableWidget.NoEditTriggers)
        self.table.setSelectionBehavior(QTableWidget.SelectRows)
        self.table.verticalHeader().setVisible(False)
        table_layout.addWidget(self.table)
        self.tabs.addTab(table_page, "采集数据")
        self.log = QPlainTextEdit()
        self.log.setReadOnly(True)
        self.log.setMaximumBlockCount(1000)
        self.tabs.addTab(self.log, "运行日志")
        self.footer = label("本地记录自动保存   ·   115200 / 8N1   ·   Windows 原生应用", "muted")
        self.footer.setWordWrap(True)
        outer.addWidget(self.footer)
        self.profile.currentIndexChanged.connect(self.profile_changed)
        self.fit.currentTextChanged.connect(self.reprepare_image)
        self.refresh_ports()
        self.profile_changed()
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.tick)
        self.timer.start(1000)
        self.write_log("工作台就绪。FPGA图片直传会先查询HXFP能力；旧版仅支持控制命令的固件需要接入图片模块。UART支持M3 v1/v2/v3与Lab4。")

    def write_log(self, message):
        self.log.appendPlainText(datetime.now().strftime("%H:%M:%S") + "  " + message)

    def open_report(self):
        from report_view import ReportDialog
        if self.report_dialog is None:
            self.report_dialog = ReportDialog(self)
        self.report_dialog.show()
        self.report_dialog.raise_()
        self.report_dialog.activateWindow()

    def problem(self, message):
        self.write_log("错误：" + message)
        self.footer.setText(message)
        QMessageBox.warning(self, "HX4S20 Studio", message)

    def refresh_ports(self):
        previous = self.port.currentData() or str(self.settings.value("port", ""))
        self.port.clear()
        self.port.addItem("请选择串口", None)
        for p in list_ports.comports():
            self.port.addItem(f"{p.device} · {p.description}", p.device)
        index = self.port.findData(previous)
        if index >= 0:
            self.port.setCurrentIndex(index)

    def start_capture(self):
        if self.capture and self.capture.isRunning():
            return
        port = self.port.currentData()
        if not port:
            self.problem("请先选择板子的串口；如果列表里没有 USB 串口，请连接适配器后刷新。")
            return
        try:
            path = data_directory() / "sessions" / (datetime.now().strftime("%Y%m%d_%H%M%S_%f") + ".sqlite3")
            self.store = SessionStore(path)
        except Exception as exc:
            self.problem("无法创建采集文件：" + str(exc))
            return
        self.table.setRowCount(0)
        self.record_count = self.total_bytes = self.old_bytes = 0
        self.last_frame = 0
        self.started = time.monotonic()
        self.plot.values = deque([0.0] * 60, maxlen=60)
        for key in self.status_fields:
            self.status_fields[key].setText("—")
        for key in ("image", "scene"):
            self.metrics[key].setText("—")
        self.metrics["count"].setText("0")
        self.metrics["bytes"].setText("0 B")
        self.export_button.setEnabled(False)
        self._capture_error = False
        self.capture = CaptureWorker(port, int(self.baud.currentText()), self.mode.currentText(), self.store, self)
        self.capture.batch.connect(self.receive_batch)
        self.capture.status.connect(self.capture_status)
        self.capture.failed.connect(self.capture_failed)
        self.capture.finished.connect(self.capture_finished)
        self.set_capture_controls(True)
        self.badge.setText("正在打开串口")
        self.write_log(f"开始采集 {port} / {self.baud.currentText()} / {self.mode.currentText()} → {path}")
        self.footer.setText("本次记录：" + str(path))
        self.settings.setValue("port", port)
        self.settings.setValue("baud", self.baud.currentText())
        self.capture.start()

    def set_capture_controls(self, active):
        self.start_button.setEnabled(not active)
        self.stop_button.setEnabled(active)
        for w in (self.port, self.baud, self.mode, self.refresh_button):
            w.setEnabled(not active)

    def capture_status(self, text):
        self.badge.setText(text)
        self.write_log(text)

    def capture_failed(self, text):
        self._capture_error = True
        self.badge.setText("采集异常 · 已停止")
        self.status_detail.setText("串口异常：" + text)
        self.write_log("串口异常：" + text)
        self.footer.setText("串口异常：" + text)

    def stop_capture(self):
        if self.capture and self.capture.isRunning():
            self.capture.stop_event.set()
            self.stop_button.setEnabled(False)
            self.badge.setText("正在停止 · 保存记录")

    def capture_finished(self):
        self.set_capture_controls(False)
        if not self._capture_error:
            self.badge.setText("已停止 · 数据已保存")
        self.write_log("串口已关闭；原始字节与解析记录已保留。")
        self.capture.deleteLater()
        self.capture = None

    def receive_batch(self, records, stats):
        self.total_bytes = stats["bytes"]
        self.record_count = stats["count"]
        self.metrics["count"].setText(f"{self.record_count:,}")
        self.metrics["bytes"].setText(self.format_bytes(self.total_bytes))
        self.status_fields["invalid"].setText(str(stats["invalid"]))
        self.export_button.setEnabled(self.record_count > 0 and self.exporter is None)
        if not records:
            return
        self.last_frame = time.monotonic()
        f = records[-1]
        self.badge.setText("采集中 · 数据正常")
        self.metrics["image"].setText(str(f.get("image_index", "—")))
        self.metrics["scene"].setText({0: "普通", 1: "提示", 2: "紧急"}.get(f.get("scene_id"), "—"))
        for key, field in (("sd", "sd_init"), ("auto", "auto_play"), ("audio", "audio_enabled")):
            value = f.get(field)
            self.status_fields[key].setText("—" if value is None else ("开启" if value else "关闭"))
        self.status_fields["brightness"].setText(str(f["brightness_percent"]) + "%" if "brightness_percent" in f else "—")
        fault = f.get("storage_fault_active")
        self.status_fields["fault"].setText("—" if fault is None else (f"故障 {f.get('storage_fault_code')}" if fault else "正常"))
        self.status_detail.setText(f"最近一帧  {f['timestamp'][11:23]}   /   {f['protocol']}\n全部数据已自动保存，可随时导出 CSV。")
        self.table.setUpdatesEnabled(False)
        for r in records:
            if self.table.rowCount() >= 300:
                self.table.removeRow(0)
            row = self.table.rowCount()
            self.table.insertRow(row)
            values = [r["timestamp"][11:23], r.get("protocol", ""), r.get("scene_id", "—"),
                      r.get("image_index", "—"), r.get("auto_play", "—"), r.get("brightness_percent", "—"),
                      r.get("raw_hex", "BMP=" + str(r.get("bmp_state", "—")))]
            for col, value in enumerate(values):
                cell = QTableWidgetItem(str(value))
                cell.setToolTip(json.dumps(r, ensure_ascii=False, indent=2))
                self.table.setItem(row, col, cell)
        self.table.setUpdatesEnabled(True)
        self.table.scrollToBottom()

    @staticmethod
    def format_bytes(value):
        if value >= 1024 * 1024:
            return f"{value / 1024 / 1024:.2f} MB"
        return f"{value / 1024:.1f} KB" if value >= 1024 else f"{value} B"

    def tick(self):
        active = self.capture is not None and self.capture.isRunning()
        rate = max(0, self.total_bytes - self.old_bytes) if active else 0
        self.old_bytes = self.total_bytes
        self.plot.values.append(rate)
        self.plot.update()
        if active:
            seconds = int(time.monotonic() - self.started)
            self.elapsed.setText(f"本次采集   {seconds // 3600:02d}:{seconds // 60 % 60:02d}:{seconds % 60:02d}")
            if time.monotonic() - (self.last_frame or self.started) > 3 and not self.capture.stop_event.is_set():
                self.badge.setText("串口已打开 · 等待有效数据")
                self.status_detail.setText("超过 3 秒未收到有效帧，状态值可能已过期。\n请检查连线、波特率和解析协议。")

    def export_csv(self):
        if not self.store or self.exporter:
            return
        path, _ = QFileDialog.getSaveFileName(self, "导出完整采集记录", "hx4s20_" + datetime.now().strftime("%Y%m%d_%H%M%S") + ".csv", "CSV (*.csv)")
        if not path:
            return
        self.exporter = ExportWorker(self.store, path, self)
        self.exporter.result.connect(self.export_result)
        self.exporter.finished.connect(self.export_finished)
        self.export_button.setEnabled(False)
        self.export_button.setText("正在导出…")
        self.exporter.start()

    def export_result(self, ok, message):
        self.write_log(message)
        self.footer.setText(message)
        if not ok:
            self.problem(message)

    def export_finished(self):
        self.exporter.deleteLater()
        self.exporter = None
        self.export_button.setText("↓  导出成 CSV")
        self.export_button.setEnabled(self.record_count > 0)

    def profile_changed(self):
        service = self.profile.currentIndex() == 1
        fpga = self.profile.currentIndex() == 2
        for b in self.control_buttons:
            b.setEnabled(not service)
        self.image_port.setEnabled(fpga and self.upload is None and self.device_probe is None)
        self.commit_wait.setEnabled(fpga and self.upload is None and self.device_probe is None)
        self.probe_button.setEnabled(fpga and self.upload is None and self.device_probe is None)
        notes = ["旧版固件仅支持控制命令。", "电脑照片服务：分包确认、重传、SHA-256校验。",
                 "图片发往独立UDP端口；需设备固件接入HXFP图片模块。"]
        hints = ["请选择FPGA图片直传模式上传到设备。", "目标电脑须启动HX4S20Receiver，端口使用左侧UDP端口。",
                 "640×480 RGB565 · 自动检测接口 · CRC32校验 · 等待设备显示提交确认"]
        self.network_note.setText(notes[self.profile.currentIndex()])
        self.transfer_note.setText(hints[self.profile.currentIndex()])
        self.upload_button.setEnabled((service or fpga) and self.image_data is not None and self.upload is None and self.device_probe is None)
        self.upload_button.setText("上传到 FPGA" if fpga else "通过以太网上传")

    def probe_fpga(self):
        if self.device_probe or self.upload:
            return
        try:
            host, port = endpoint(self.host.text().strip(), self.image_port.value())
        except ValueError as exc:
            self.problem(str(exc))
            return
        self.device_probe = DeviceProbeWorker(host, port, self)
        self.device_probe.result.connect(self.probe_result)
        self.device_probe.finished.connect(self.probe_finished)
        for w in (self.probe_button, self.host, self.image_port, self.profile, self.upload_button):
            w.setEnabled(False)
        self.probe_button.setText("正在查询设备…")
        self.write_log(f"查询图片接收能力 → {host}:{port}")
        self.device_probe.start()

    def probe_result(self, ok, message):
        self.network_note.setText(message)
        self.write_log(message)
        self.footer.setText(message)

    def probe_finished(self):
        self.device_probe.deleteLater()
        self.device_probe = None
        self.probe_button.setText("检测设备图片接口")
        for w in (self.probe_button, self.host, self.image_port, self.profile):
            w.setEnabled(True)
        self.upload_button.setEnabled(self.image_data is not None and self.profile.currentIndex() in (1, 2))

    def choose_image(self):
        path, _ = QFileDialog.getOpenFileName(self, "选择照片", "", "照片 (*.jpg *.jpeg *.png *.bmp *.webp)")
        if path:
            self.image_path = Path(path)
            self.reprepare_image()

    def reprepare_image(self):
        if self.image_path is None:
            return
        try:
            self.image_data = prepare_image(self.image_path, self.fit.currentText())
            self.render_preview()
            self.photo_info.setText(f"{self.image_path.name}   /   640 × 480   /   24-bit BMP   /   {len(self.image_data):,} bytes")
            self.save_image_button.setEnabled(True)
            self.progress.setValue(0)
            self.profile_changed()
        except Exception as exc:
            self.image_data = None
            self.save_image_button.setEnabled(False)
            self.upload_button.setEnabled(False)
            self.preview.clear()
            self.photo_info.setText("照片读取失败")
            self.problem("无法读取照片：" + str(exc))

    def render_preview(self):
        if self.image_data:
            pixmap = QPixmap()
            pixmap.loadFromData(self.image_data, "BMP")
            self.preview.setPixmap(pixmap.scaled(max(100, self.preview.width() - 20), max(100, self.preview.height() - 20), Qt.KeepAspectRatio, Qt.SmoothTransformation))

    def resizeEvent(self, event):
        super().resizeEvent(event)
        if hasattr(self, "preview"):
            QTimer.singleShot(0, self.render_preview)

    def save_bmp(self):
        if not self.image_data:
            return
        path, _ = QFileDialog.getSaveFileName(self, "保存兼容 BMP", self.image_path.stem + "_640x480.bmp", "BMP (*.bmp)")
        if path:
            try:
                Path(path).write_bytes(self.image_data)
                self.write_log("BMP 已保存：" + path)
                self.footer.setText("BMP 已保存：" + path)
            except OSError as exc:
                self.problem(str(exc))

    def send_command(self, opcode, name):
        try:
            target = endpoint(self.host.text().strip(), self.netport.value())
            packet = command_packet(opcode, self.sequence)
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
                sock.sendto(packet, target)
            self.sequence = (self.sequence + 1) & 255
            text = f"{name} 已发送至 {target[0]}:{target[1]}，无设备 ACK；请观察 UART 或板上效果。"
            self.write_log(text + "  [" + packet.hex(" ") + "]")
            self.footer.setText(text)
        except Exception as exc:
            self.problem("网络发送失败：" + str(exc))

    def start_upload(self):
        if not self.image_data or self.upload or self.device_probe or self.profile.currentIndex() not in (1, 2):
            return
        try:
            host, port = endpoint(self.host.text().strip(), self.image_port.value() if self.profile.currentIndex() == 2 else self.netport.value())
        except ValueError as exc:
            self.problem("目标地址无效：" + str(exc))
            return
        self.upload = UploadWorker(host, port, self.image_data, self.image_path.name, self,
                                   fpga=self.profile.currentIndex() == 2, commit_timeout=self.commit_wait.value())
        self.upload.progress.connect(self.upload_progress)
        self.upload.stage.connect(self.upload_stage)
        self.upload.result.connect(self.upload_result)
        self.upload.finished.connect(self.upload_finished)
        for w in (self.choose_button, self.fit, self.upload_button, self.profile, self.host, self.netport, self.image_port, self.commit_wait, self.probe_button, *self.control_buttons):
            w.setEnabled(False)
        self.cancel_button.setEnabled(True)
        self.progress.setValue(0)
        self.transfer_note.setText("正在等待照片接收服务确认…")
        self.write_log(f"照片传输开始 → {host}:{port}，{len(self.image_data):,} bytes")
        self.upload.start()

    def upload_stage(self, message):
        self.transfer_note.setText(message)
        self.write_log(message)
        if "帧边界显示提交" in message:
            self.cancel_button.setEnabled(False)

    def upload_progress(self, done, total):
        self.progress.setValue(min(99, done * 100 // total))
        self.transfer_note.setText(f"分包已确认 {done:,} / {total:,} bytes；等待最终完整性确认。")

    def cancel_upload(self):
        if self.upload:
            self.upload.stop_event.set()
            self.cancel_button.setEnabled(False)

    def upload_result(self, ok, text):
        if ok:
            self.progress.setValue(100)
        success = "上传完成 · 设备已确认显示提交" if self.upload and self.upload.is_fpga else "上传完成 · 接收端已校验"
        self.transfer_note.setText(success if ok else "传输未完成 · " + text)
        self.write_log(text)
        self.footer.setText(text)

    def upload_finished(self):
        self.upload.deleteLater()
        self.upload = None
        for w in (self.choose_button, self.fit, self.profile, self.host, self.netport):
            w.setEnabled(True)
        self.upload_button.setEnabled(self.image_data is not None and self.profile.currentIndex() in (1, 2))
        self.image_port.setEnabled(self.profile.currentIndex() == 2)
        self.commit_wait.setEnabled(self.profile.currentIndex() == 2)
        self.probe_button.setEnabled(self.profile.currentIndex() == 2)
        for b in self.control_buttons:
            b.setEnabled(self.profile.currentIndex() != 1)
        self.cancel_button.setEnabled(False)

    def closeEvent(self, event):
        if self.report_dialog is not None:
            self.report_dialog.pause()
            if self.report_dialog.export_worker and self.report_dialog.export_worker.isRunning():
                event.ignore()
                self.footer.setText("正在完成历史记录CSV导出…")
                QTimer.singleShot(150, self.close)
                return
        running = []
        for worker in (self.capture, self.upload, self.exporter, self.device_probe):
            if worker is not None and worker.isRunning():
                if hasattr(worker, "stop_event"):
                    worker.stop_event.set()
                running.append(worker)
        if running:
            event.ignore()
            self._closing = True
            self.setEnabled(False)
            self.footer.setText("正在保存记录并关闭连接…")
            QTimer.singleShot(150, self.close)
            return
        self.settings.setValue("host", self.host.text())
        self.settings.setValue("netport", self.netport.value())
        self.settings.setValue("image_port", self.image_port.value())
        self.settings.setValue("commit_wait", self.commit_wait.value())
        event.accept()


def make_icon():
    pixmap = QPixmap(64, 64)
    pixmap.fill(QColor("#10223b"))
    painter = QPainter(pixmap)
    painter.setRenderHint(QPainter.Antialiasing)
    painter.setPen(QPen(QColor("#65d9f5"), 3))
    painter.drawRoundedRect(14, 14, 36, 36, 6, 6)
    for i in (22, 32, 42):
        for a, b, c, d in ((5, i, 14, i), (50, i, 59, i), (i, 5, i, 14), (i, 50, i, 59)):
            painter.drawLine(a, b, c, d)
    painter.setFont(QFont("Segoe UI", 15, QFont.Bold))
    painter.drawText(pixmap.rect(), Qt.AlignCenter, "HX")
    painter.end()
    return QIcon(pixmap)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--smoke-test", type=Path, help="render window, record result and exit without hardware access")
    parser.add_argument("--report-capture", type=Path, help="capture actual evidence archive pages without hardware access")
    parser.add_argument("--send-image", type=Path, help="upload an image using HXFP without opening the GUI")
    parser.add_argument("--device-ip", help="explicit target IPv4 required for --send-image")
    parser.add_argument("--image-port", type=int, default=5002)
    parser.add_argument("--transfer-records", type=Path, help="optional transfer receipt directory")
    parser.add_argument("--ack-timeout", type=float, default=0.7, help="seconds per data ACK attempt")
    parser.add_argument("--commit-timeout", type=float, default=3.0, help="seconds per display COMMIT attempt")
    parser.add_argument("--attempts", type=int, default=6, help="maximum transmissions per request")
    args = parser.parse_args()
    if args.send_image:
        if not args.device_ip:
            parser.error("--send-image requires --device-ip")
        from fpga_transfer import upload_to_fpga
        upload_to_fpga(args.device_ip, args.image_port, prepare_image(args.send_image), args.send_image.name,
                       receipt_dir=args.transfer_records, timeout=args.ack_timeout,
                       commit_timeout=args.commit_timeout, retries=args.attempts)
        return 0
    QApplication.setAttribute(Qt.AA_EnableHighDpiScaling)
    app = QApplication(sys.argv[:1])
    app.setStyle("Fusion")
    app.setStyleSheet(STYLE)
    app.setWindowIcon(make_icon())
    capture_root = args.smoke_test or args.report_capture
    capture_settings = None
    if capture_root:
        capture_root.mkdir(parents=True, exist_ok=True)
        capture_settings = QSettings(str(capture_root / "capture-settings.ini"), QSettings.IniFormat)
        capture_settings.clear()
    window = MainWindow(settings=capture_settings)
    window.show()
    if args.report_capture:
        def capture_report():
            window.open_report()
            def save_pages():
                names = window.report_dialog.capture_pages(args.report_capture)
                (args.report_capture / "截图收据.json").write_text(json.dumps({"kind": "actual_application_screenshots", "packaged_executable": bool(getattr(sys, "frozen", False)), "hardware_opened": False, "pages": names, "source": "历史原始记录与报告摘录"}, ensure_ascii=False, indent=2), encoding="utf-8")
                window.report_dialog.close()
                window.close()
            QTimer.singleShot(800, save_pages)
        QTimer.singleShot(600, capture_report)
    if args.smoke_test:
        def smoke():
            args.smoke_test.mkdir(parents=True, exist_ok=True)
            window.grab().save(str(args.smoke_test / "desktop.png"))
            (args.smoke_test / "startup.json").write_text(json.dumps({"ok": True, "title": window.windowTitle(), "ports": window.port.count() - 1, "hardware_opened": False}, ensure_ascii=False, indent=2), encoding="utf-8")
            window.close()
        QTimer.singleShot(1000, smoke)
    return app.exec_()


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        (data_directory() / "crash.log").write_text(traceback.format_exc(), encoding="utf-8")
        raise
