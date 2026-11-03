"""Evidence browser: actual historical logs, report claims, and provenance-aware CSV."""
import csv
import gzip
import hashlib
import json
import math
import os
from pathlib import Path
import tempfile

from PyQt5.QtCore import Qt, QThread, QTimer, pyqtSignal
from PyQt5.QtGui import QColor, QFont, QPainter, QPen
from PyQt5.QtWidgets import (QComboBox, QDialog, QFileDialog, QFrame, QGridLayout, QHBoxLayout,
                             QHeaderView, QLabel, QMessageBox, QPushButton, QScrollArea, QSlider, QTableWidget,
                             QTableWidgetItem, QTabWidget, QVBoxLayout, QWidget)


DATA = Path(__file__).resolve().parent / "report_data"


def load_manifest():
    return json.loads((DATA / "manifest.json").read_text(encoding="utf-8"))


def trace_source(trace):
    # Source checkout uses the shared dataset; PyInstaller stores it beside report_data.
    source = DATA / trace["source"]
    if not source.is_file() and trace.get("id") == "final-72h":
        source = DATA.parent / "long_run_data" / "parsed.jsonl.gz"
    return source


def export_trace(manifest, index, destination):
    trace = manifest["traces"][index]
    source = trace_source(trace)
    with source.open("rb") as stream:
        actual_hash = hashlib.file_digest(stream, "sha256").hexdigest()
    if actual_hash != trace["source_sha256"]:
        raise ValueError("历史源文件 SHA-256 不匹配")
    opener = gzip.open if source.suffix == ".gz" else open
    fields = set()
    with opener(source, "rt", encoding="utf-8") as stream:
        for line in stream:
            row = json.loads(line)
            if row.get("kind") == "status":
                fields.update(row)
    names = ["evidence_type", "source_file", "source_sha256", "original_timestamp"] + sorted(fields)
    target = Path(destination)
    count = 0
    fd, temp = tempfile.mkstemp(prefix=target.name + ".", suffix=".tmp", dir=target.parent)
    try:
        with os.fdopen(fd, "w", newline="", encoding="utf-8-sig") as output, opener(source, "rt", encoding="utf-8") as stream:
            writer = csv.DictWriter(output, fieldnames=names)
            writer.writeheader()
            for line in stream:
                row = json.loads(line)
                if row.get("kind") == "status":
                    writer.writerow({"evidence_type": "历史实测记录", "source_file": trace["repository_source"],
                                     "source_sha256": trace["source_sha256"], "original_timestamp": row["timestamp"], **row})
                    count += 1
        os.replace(temp, target)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)
    return count


class ArchiveExport(QThread):
    completed = pyqtSignal(bool, str)

    def __init__(self, manifest, index, path, parent):
        super().__init__(parent)
        self.args = manifest, index, path

    def run(self):
        try:
            count = export_trace(*self.args)
            self.completed.emit(True, f"已导出 {count:,} 条完整历史记录，包含原始时间和来源。")
        except Exception as exc:
            self.completed.emit(False, "导出失败：" + str(exc))


def text(value, name=None):
    item = QLabel(value)
    if name:
        item.setObjectName(name)
    return item


def wrapped(value, name="muted"):
    item = text(value, name)
    item.setWordWrap(True)
    return item


def panel(title=None):
    frame = QFrame()
    frame.setObjectName("card")
    layout = QVBoxLayout(frame)
    layout.setContentsMargins(18, 15, 18, 15)
    if title:
        layout.addWidget(text(title, "section"))
    return frame, layout


def action(title, callback, primary=False):
    b = QPushButton(title)
    if primary:
        b.setObjectName("primary")
    b.setCursor(Qt.PointingHandCursor)
    b.clicked.connect(callback)
    return b


def metric_row(items):
    row = QHBoxLayout()
    for title, value, note in items:
        frame, layout = panel()
        layout.addWidget(text(title, "muted"))
        layout.addWidget(text(value, "metric"))
        layout.addWidget(wrapped(note))
        row.addWidget(frame)
    return row


def table(headers, rows):
    widget = QTableWidget(len(rows), len(headers))
    widget.setHorizontalHeaderLabels(headers)
    widget.setAlternatingRowColors(True)
    widget.setEditTriggers(QTableWidget.NoEditTriggers)
    widget.setSelectionBehavior(QTableWidget.SelectRows)
    widget.setSelectionMode(QTableWidget.SingleSelection)
    widget.verticalHeader().setVisible(False)
    widget.verticalHeader().setDefaultSectionSize(37)
    widget.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
    for i, row in enumerate(rows):
        for j, value in enumerate(row):
            widget.setItem(i, j, QTableWidgetItem(str(value)))
    return widget


class EvidenceChart(QWidget):
    def __init__(self, values, unit, bars=False, labels=None):
        super().__init__()
        self.values = values
        self.unit = unit
        self.bars = bars
        self.labels = labels
        self.cursor = None
        self.setMinimumHeight(180)
        self.setAccessibleName(unit + "；原始记录统计")

    def paintEvent(self, _):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.fillRect(self.rect(), QColor("#10223b"))
        left, top, width, height = 56, 24, self.width() - 80, self.height() - 60
        ceiling = max(1, max(self.values, default=1)) * 1.2
        p.setFont(QFont("Microsoft YaHei UI", 10))
        for step in range(5):
            y = top + height * step / 4
            p.setPen(QColor("#29435e"))
            p.drawLine(left, int(y), left + width, int(y))
            p.setPen(QColor("#a7bed7"))
            p.drawText(3, int(y + 4), f"{ceiling * (4 - step) / 4:.1f}")
        p.drawText(left, 15, self.unit)
        n = len(self.values)
        for i, value in enumerate(self.values):
            if self.bars:
                step = width / max(1, n)
                x = left + (i + 0.2) * step
                bar_height = height * value / ceiling
                p.fillRect(int(x), int(top + height - bar_height), int(step * 0.6), int(bar_height), QColor("#3cb9eb"))
                p.setPen(QColor("#e5f1ff"))
                p.drawText(int(x), int(top + height - bar_height - 10), f"{value:.5f}")
                p.setPen(QColor("#a7bed7"))
                p.drawText(int(x), self.height() - 10, self.labels[i] if self.labels else str(i + 1))
            elif i:
                x0 = left + (i - 1) * width / max(1, n - 1)
                x1 = left + i * width / max(1, n - 1)
                y0 = top + height * (1 - self.values[i - 1] / ceiling)
                y1 = top + height * (1 - value / ceiling)
                p.setPen(QPen(QColor("#52d5e6"), 2))
                p.drawLine(int(x0), int(y0), int(x1), int(y1))
        if not self.bars:
            p.setPen(QColor("#a7bed7"))
            p.drawText(left, self.height() - 10, "0 min")
            p.drawText(left + width // 2 - 20, self.height() - 10, f"{(n - 1) / 2:.0f} min")
            p.drawText(left + width - 42, self.height() - 10, f"{n - 1} min")


class ReportDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.manifest = load_manifest()
        self.setWindowTitle("红色数字展馆 · 测试档案 | HX4S20 Studio")
        self.resize(1420, 940)
        self.setMinimumSize(1060, 760)
        self.export_worker = None
        self.out = QVBoxLayout(self)
        self.out.setContentsMargins(24, 20, 24, 18)
        self.out.setSpacing(16)
        title = QHBoxLayout()
        heading = QVBoxLayout()
        heading.addWidget(text("红色数字展馆  /  测试档案", "title"))
        heading.addWidget(text("瞬应逻辑队    ·    HX4S20 STUDIO    ·    作品设计报告配套证据", "subtitle"))
        title.addLayout(heading)
        title.addStretch()
        title.addWidget(text("历史实测 + 文档证据", "badge"))
        self.out.addLayout(title)
        self.tabs = QTabWidget()
        self.out.addWidget(self.tabs, 1)
        self.build_overview()
        self.build_history()
        self.build_latency()
        self.build_optimizations()
        self.build_long_run_plan()
        self.build_sources()
        self.footer = wrapped("资料更新：2026-11-03   |   72小时长稳测试 · 完整日志已归档   |   本页离线回放")
        self.out.addWidget(self.footer)
        self.play_timer = QTimer(self)
        self.play_timer.setInterval(180)
        self.play_timer.timeout.connect(self.advance)
        self.select_trace(0)

    def page(self, name):
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setContentsMargins(18, 18, 18, 16)
        layout.setSpacing(14)
        if name == "来源与版本":
            scroll = QScrollArea()
            scroll.setWidgetResizable(True)
            scroll.setFrameShape(QFrame.NoFrame)
            scroll.setWidget(widget)
            self.tabs.addTab(scroll, name)
        else:
            self.tabs.addTab(widget, name)
        return layout

    def build_overview(self):
        layout = self.page("测试总览")
        current = self.manifest["traces"][0]
        layout.addLayout(metric_row([
            ("测试项", str(len(self.manifest["cases"])), "稳定性 · 响应 · 优化成果 · 长时计划"),
            ("72小时状态记录", f"{current['records']:,}", "2026-10-28～31 · 完整日志重算"),
            ("长稳样本跨度", f"约 {current['span_seconds']/3600:.0f} h", f"精确跨度 {current['span_seconds']:,.6f} 秒"),
            ("测试类别", "最终版本", "72小时长稳测试"),
        ]))
        row = QHBoxLayout()
        row.addWidget(text("测试矩阵与证据索引", "section"))
        row.addStretch()
        self.filter = QComboBox()
        self.filter.addItems(["全部测试项", "原始日志核验", "报告记载", "理论计算", "网络优化", "音画优化", "资源优化", "上位机", "测试计划", "待验证"])
        self.filter.currentTextChanged.connect(self.filter_cases)
        row.addWidget(self.filter)
        row.addWidget(action("导出测试集 CSV", self.export_cases))
        layout.addLayout(row)
        cases = self.manifest["cases"]
        self.cases_table = table(["编号", "测试项", "结果 / 数值", "证据类型"],
                                 [[c["id"], c["title"], c["result"], c["evidence"]] for c in cases])
        self.cases_table.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeToContents)
        self.cases_table.setColumnWidth(0, 65)
        self.cases_table.itemSelectionChanged.connect(self.case_selected)
        layout.addWidget(self.cases_table, 1)
        frame, inside = panel("选中项 · 方法与来源")
        self.case_detail = wrapped("")
        self.case_detail.setTextInteractionFlags(Qt.TextSelectableByMouse)
        inside.addWidget(self.case_detail)
        layout.addWidget(frame)
        self.cases_table.selectRow(0)

    def filter_cases(self, name):
        for i, c in enumerate(self.manifest["cases"]):
            show = name == "全部测试项" or name in c["evidence"] or name in c["group"]
            self.cases_table.setRowHidden(i, not show)

    def case_selected(self):
        index = self.cases_table.currentRow()
        if index >= 0:
            c = self.manifest["cases"][index]
            self.case_detail.setText(f"{c['id']}  {c['method']}\n来源：{c['source']}\n适用范围：{c['scope']}")

    def export_cases(self):
        path, _ = QFileDialog.getSaveFileName(self, "导出测试集", "红色数字展馆_测试用例与证据.csv", "CSV (*.csv)")
        if path:
            try:
                with open(path, "w", newline="", encoding="utf-8-sig") as stream:
                    cases = self.manifest["cases"]
                    writer = csv.DictWriter(stream, fieldnames=list(cases[0]))
                    writer.writeheader()
                    writer.writerows(cases)
                self.footer.setText(f"{len(cases)}项测试及其来源已导出：" + path)
            except OSError as exc:
                QMessageBox.warning(self, "导出失败", str(exc))

    def build_history(self):
        layout = self.page("历史记录回放")
        long = self.manifest["traces"][0]
        layout.addLayout(metric_row([
            ("最终版本状态记录", f"{long['records']:,}", "72小时JSONL完整统计"),
            ("样本跨度", f"{long['span_seconds']/3600:.2f} h", "2026-10-28～31 · 北京时间"),
            ("摘要无效数 / 故障记录", f"{long['summary']['invalid']} / {long['fault_rows']}", "invalid为日志摘要；fault逐条重算"),
            ("图片索引变化", f"{long['index_changes']:,}", "覆盖0、1、2、3四个索引"),
        ]))
        frame, inside = panel("最终版本72小时趋势 · 每分钟图片索引变化次数")
        self.long_chart = EvidenceChart([b["changes"] for b in long["minute_bins"]], "次 / 分钟")
        inside.addWidget(self.long_chart)
        layout.addWidget(frame)
        row = QHBoxLayout()
        self.trace_choice = QComboBox()
        self.trace_choice.addItems([t["label"] for t in self.manifest["traces"]])
        self.trace_choice.currentIndexChanged.connect(self.select_trace)
        row.addWidget(self.trace_choice, 1)
        self.play_button = action("开始回放", self.play, True)
        self.pause_button = action("停止回放", self.pause)
        self.csv_button = action("导出完整记录 CSV", self.export_history)
        for b in (self.play_button, self.pause_button, self.csv_button):
            row.addWidget(b)
        layout.addLayout(row)
        self.slider = QSlider(Qt.Horizontal)
        self.slider.valueChanged.connect(self.show_sample)
        self.slider.setAccessibleName("历史记录回放位置")
        layout.addWidget(self.slider)
        self.history_info = wrapped("")
        layout.addWidget(self.history_info)
        self.sample_table = table(["原始时间（含时区）", "原记录号", "场景", "图片", "轮播", "亮度", "音频", "故障"], [])
        self.sample_table.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeToContents)
        layout.addWidget(self.sample_table, 1)

    def select_trace(self, index):
        if not hasattr(self, "slider"):
            return
        if hasattr(self, "play_timer"):
            self.pause()
        trace = self.manifest["traces"][index]
        self.slider.setRange(0, len(trace["samples"]) - 1)
        self.slider.setValue(len(trace["samples"]) - 1)
        self.show_sample(self.slider.value())

    def show_sample(self, index):
        trace = self.manifest["traces"][self.trace_choice.currentIndex()]
        sample = trace["samples"][index]
        self.history_info.setText(f"{trace['label']}  |  原记录 {sample['record_number']:,} / {trace['records']:,}  |  原始时间 {sample['timestamp']}\n"
                                  f"显示每{trace['display_stride']}条取1条及末条；CSV导出全部原始状态。{trace['note']}")
        samples = trace["samples"][max(0, index - 7):index + 1]
        self.sample_table.setRowCount(len(samples))
        for i, row in enumerate(samples):
            yes = lambda key: "—" if key not in row else ("开启" if row[key] else "关闭")
            values = [row["timestamp"], row["record_number"], {0: "普通", 1: "提示", 2: "紧急"}.get(row.get("scene_id"), "—"),
                      row.get("image_index", "—"), yes("auto_play"), str(row.get("brightness_percent", "—")),
                      yes("audio_enabled"), row.get("storage_fault_code", "—")]
            for j, value in enumerate(values):
                item = QTableWidgetItem(str(value))
                item.setToolTip(json.dumps(row, ensure_ascii=False, indent=2))
                self.sample_table.setItem(i, j, item)
        self.sample_table.scrollToBottom()

    def play(self):
        if self.slider.value() == self.slider.maximum():
            self.slider.setValue(0)
        self.play_timer.start()
        self.play_button.setEnabled(False)
        self.footer.setText("历史记录按快照步进回放，回放速度不代表实际采集间隔。未连接设备。")

    def pause(self):
        self.play_timer.stop()
        self.play_button.setEnabled(True)

    def advance(self):
        value = self.slider.value() + 1
        self.slider.setValue(min(value, self.slider.maximum()))
        if value >= self.slider.maximum():
            self.pause()

    def export_history(self):
        if self.export_worker:
            return
        index = self.trace_choice.currentIndex()
        path, _ = QFileDialog.getSaveFileName(self, "导出完整历史记录", self.manifest["traces"][index]["label"] + "_历史实测.csv", "CSV (*.csv)")
        if not path:
            return
        self.export_worker = ArchiveExport(self.manifest, index, path, self)
        self.export_worker.completed.connect(self.export_result)
        self.export_worker.finished.connect(self.export_done)
        self.csv_button.setEnabled(False)
        self.csv_button.setText("正在导出全部记录…")
        self.export_worker.start()

    def export_result(self, ok, message):
        self.footer.setText(message)
        if not ok:
            QMessageBox.warning(self, "历史记录导出", message)

    def export_done(self):
        self.export_worker.deleteLater()
        self.export_worker = None
        self.csv_button.setEnabled(True)
        self.csv_button.setText("导出完整记录 CSV")

    def build_latency(self):
        layout = self.page("事件延迟分析")
        stats = self.manifest["latency"]
        layout.addLayout(metric_row([
            ("独立事件样本", "4", "2026-10-01 · COM39 · 提示场景"),
            ("平均内部提交延迟", f"{stats['mean_ms']:.5f} ms", "请求接受 → scene_commit"),
            ("最小值", f"{stats['min_ms']:.5f} ms", "第三次提示事件"),
            ("最大值", f"{stats['max_ms']:.5f} ms", "第二次提示事件"),
        ]))
        frame, inside = panel("四次真实事件 · 内部提交延迟")
        chart = EvidenceChart(stats["values_ms"], "内部提交延迟 / ms", True, ["事件 1", "事件 2", "事件 3", "事件 4"])
        chart.setMinimumHeight(230)
        inside.addWidget(chart)
        layout.addWidget(frame, 1)
        events = next(t for t in self.manifest["traces"] if t["label"] == "M3 场景响应")["events"]
        self.event_table = table(["请求编号", "原始记录时间", "场景", "片内延迟 / ms"],
                                 [[e["request_count"], e["timestamp"], "提示", f"{e['internal_commit_ms']:.5f}"] for e in events])
        self.event_table.setMaximumHeight(210)
        self.event_table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeToContents)
        layout.addWidget(self.event_table)
        layout.addWidget(wrapped("来源：m3-uart-20261001-152024.jsonl；4个独立请求对应的提交快照。样本量 n=4，不外推为千次事件分布；不含机械消抖、网络传输及显示器响应。"))

    def build_sources(self):
        layout = self.page("来源与版本")
        report = self.manifest["report"]
        frame, inside = panel("设计报告")
        frame.setMinimumHeight(125)
        inside.addWidget(wrapped(report["title"]))
        inside.addWidget(wrapped(f"Word 共{report['pages']}页；对应章节：{report['sections']}\n文件 SHA-256：{report['sha256']}"))
        layout.addWidget(frame)
        for trace in self.manifest["traces"]:
            frame, inside = panel(trace["label"] + " · 历史实测")
            frame.setMinimumHeight(140)
            inside.addWidget(wrapped(f"{trace['repository_source']}\n{trace['first']} → {trace['last']}\n{trace['records']:,}条原始状态；SHA-256：{trace['source_sha256']}\n{trace['note']}"))
            layout.addWidget(frame)
        layout.addWidget(wrapped("本项目已完成72小时长稳测试，完整日志与重算结果已归档。旧M3/M5会话及报告摘录保留各自日期，当前构建指标见根目录验证说明。"))
        layout.addStretch()

    def build_optimizations(self):
        layout = self.page("设计优化与实现")
        budget = self.manifest["network_budget"]
        improvement = (1 - budget["after_ms"] / budget["before_ms"]) * 100
        layout.addLayout(metric_row([
            ("SPI线上时间降幅", f"{improvement:.2f}%", "理论预算 · 2071B / 6.25MHz"),
            ("SPI吞吐比值", f"{budget['before_ms']/budget['after_ms']:.2f} ×", "相同载荷，不含TCP与浏览器"),
            ("当前 Setup 裕量", "+0.156 ns", "当前提交版本路由后结果"),
            ("频谱与开屏", "实时频谱 / 开场视频", "FFT 音频分析与连续图像帧播放"),
        ]))
        values = self.manifest["extensions"]["optimizations"]
        self.optimization_table = table(["优化项", "优化前", "优化后", "数据依据"],
                                       [[o["name"], o["before"], o["after"], o["basis"]] for o in values])
        for i, o in enumerate(values):
            for j in range(4):
                self.optimization_table.item(i, j).setToolTip(o["note"])
        self.optimization_table.setMaximumHeight(310)
        layout.addWidget(self.optimization_table)
        frame, inside = panel("首页 SPI 写入时间 · 相同条件的理论比较")
        chart = EvidenceChart([budget["before_ms"], budget["after_ms"]], "SPI串行传输预算 / ms", True, ["逐字节写入", "9次突发写入"])
        inside.addWidget(chart)
        layout.addWidget(frame, 1)
        layout.addWidget(wrapped("本页为历史报告中的优化对比，数值按其来源版本解释；当前冻结位流为Setup +0.156 ns、Hold +0.022 ns、LUT 16,474。最终版本72小时实测见“历史记录回放”，旧M3/M5会话单独保留。"))

    def build_long_run_plan(self):
        layout = self.page("72h实测 / 历史计划")
        current = self.manifest["traces"][0]
        layout.addWidget(text("最终版本约72小时实测已完成 · 下表为历史组合场景预算", "badge"))
        layout.addWidget(wrapped(f"实测 {current['records']:,} 条状态，跨度 {current['span_seconds']:,.6f} 秒，存储故障记录 {current['fault_rows']}。未逐项核对的组合场景仍保留计划属性。"))
        plans = self.manifest["extensions"]["plans"]
        layout.addLayout(metric_row([(f"{p['target_hours']} 小时目标", f"{p['planned_frames']:,} 帧",
                                      f"原始数据 {p['raw_bytes']/1048576:.2f} MiB · 历史预算") for p in plans]))
        self.plan_table = table(["目标时长", "预算速率", "帧预算", "原始数据", "实际运行时长", "验收结果"],
                               [[f"{p['target_hours']} h", "20Hz / 64B", f"{p['planned_frames']:,}",
                                 f"{p['raw_bytes']/1048576:.2f} MiB", "见上方72h实测", "组合场景待逐项核对"] for p in plans])
        self.plan_table.setMaximumHeight(180)
        layout.addWidget(self.plan_table)
        frame, inside = panel("建议覆盖的组合场景")
        self.phase_table = table(["阶段", "工作负载", "检查点"], [
            ["基础运行", "四图轮播 + PCM音频 + FFT", "画面、音频、写完成、fault/recovery"],
            ["网络控制", "网页长连接 + UDP + 亮度/音频操作", "请求与动作一致；记录每次起止点"],
            ["高优先级事件", "转场中提示/紧急/清除", "优先级、返回状态、轮播停止规则"],
            ["异常与恢复", "经确认的无卡/读超时等故障注入", "故障码、恢复次数及音画观察"],
            ["长稳收尾", "停止采集、导出CSV、归档版本哈希", "实际起止时间、记录数、缺失与错误"],
        ])
        inside.addWidget(self.phase_table)
        layout.addWidget(frame, 1)
        row = QHBoxLayout()
        row.addWidget(wrapped("预算假设：连续20Hz、UART v3每帧64B、8N1；线路需求12,800bit/s。稳定时1Hz心跳会产生更少记录。CSV/SQLite大小另计。"), 1)
        row.addWidget(action("导出长时测试计划", self.export_plans))
        layout.addLayout(row)
        layout.addWidget(wrapped("原计划按20Hz计算容量；当前实测来自完整日志。旧计划CSV保留原始空结果字段，用于追溯计划，不代表当前72小时测试尚未完成。"))

    def export_plans(self):
        path, _ = QFileDialog.getSaveFileName(self, "导出长时计划", "长时测试计划_未执行.csv", "CSV (*.csv)")
        if path:
            try:
                plans = self.manifest["extensions"]["plans"]
                with open(path, "w", encoding="utf-8-sig", newline="") as output:
                    writer = csv.DictWriter(output, fieldnames=list(plans[0]))
                    writer.writeheader()
                    writer.writerows(plans)
                self.footer.setText("长时测试计划已导出，实测时长与通过结果为空：" + path)
            except OSError as exc:
                QMessageBox.warning(self, "导出失败", str(exc))

    def capture_pages(self, destination):
        destination = Path(destination)
        destination.mkdir(parents=True, exist_ok=True)
        self.pause()
        from PyQt5.QtWidgets import QApplication
        names = ["01_测试总览", "02_长稳历史记录", "03_事件延迟分析", "04_后续优化成果", "05_长时扩展计划", "06_来源与版本"]
        for i, name in enumerate(names):
            self.tabs.setCurrentIndex(i)
            QApplication.processEvents()
            if not self.grab().save(str(destination / (name + ".png"))):
                raise OSError("截图写入失败")
        self.tabs.setCurrentIndex(0)
        return names

    def closeEvent(self, event):
        self.pause()
        if self.export_worker and self.export_worker.isRunning():
            self.footer.setText("正在完成CSV导出，请稍候关闭。")
            event.ignore()
            return
        event.accept()
