"""Build the report archive from actual repository evidence; never synthesize UART rows."""
import csv
from datetime import datetime
import gzip
import hashlib
import json
from pathlib import Path
import shutil
from report_extensions import extend_cases

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent
OUT = ROOT / "report_data"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_trace(relative, label, note, stride=1):
    path = REPO / relative
    destination = OUT / "sources" / path.name
    shutil.copyfile(path, destination)
    opener = gzip.open if path.suffix == ".gz" else open
    raw_hash = hashlib.sha256()
    count = faults = changes = 0
    first = last = previous_image = None
    samples, events, bins = [], [], {}
    summary = {}
    previous_request = 0
    with opener(path, "rb") as stream:
        for line in stream:
            raw_hash.update(line)
            row = json.loads(line)
            if row.get("kind") == "summary":
                summary = row
                continue
            if row.get("kind") != "status":
                continue
            seconds = datetime.fromisoformat(row["timestamp"]).timestamp()
            if first is None:
                first = row
                first_time = seconds
            minute = int((seconds - first_time) // 60)
            bucket = bins.setdefault(minute, {"minute": minute, "records": 0, "changes": 0, "faults": 0})
            bucket["records"] += 1
            fault = int(bool(row.get("storage_fault_active", False)))
            bucket["faults"] += fault
            faults += fault
            image = row.get("image_index")
            if previous_image is not None and image != previous_image:
                changes += 1
                bucket["changes"] += 1
            previous_image = image
            count += 1
            if (count - 1) % stride == 0:
                samples.append({"record_number": count, **row})
            req = row.get("request_count", 0)
            if (row.get("scene_id") in (1, 2) and row.get("latency_valid")
                    and not row.get("request_pending") and req == previous_request + 1):
                events.append({"timestamp": row["timestamp"], "request_count": req,
                               "scene_id": row["scene_id"], "internal_commit_ms": row["internal_commit_ms"]})
                previous_request = req
            last = row
    if samples[-1]["record_number"] != count:
        samples.append({"record_number": count, **last})
    return {"label": label, "note": note, "source": "sources/" + path.name,
            "repository_source": relative, "source_sha256": digest(path), "raw_sha256": raw_hash.hexdigest(),
            "records": count, "fault_rows": faults, "index_changes": changes,
            "first": first["timestamp"], "last": last["timestamp"],
            "span_seconds": datetime.fromisoformat(last["timestamp"]).timestamp() - first_time,
            "summary": summary, "samples": samples, "display_stride": stride,
            "events": events, "minute_bins": list(bins.values())}


def main():
    (OUT / "sources").mkdir(parents=True, exist_ok=True)
    doc = json.loads((ROOT / "evidence/report_source/paragraphs.json").read_text(encoding="utf-8"))
    doc_path = Path(doc["path"])
    report = {"title": doc_path.stem, "sha256": digest(doc_path), "pages": doc["pages"],
              "sections": "3.3 / 表3-2、表3-3、表3-4；2.3 网络优化", "source_kind": "Word 设计报告摘录"}
    traces = [
        load_trace("diagnostics/m5-two-hour-com8-20261003.jsonl.gz", "M5 长时间运行", "2026-10-02～03 历史版本；音频多数关闭，轮播并非全程开启。", 100),
        load_trace("diagnostics/m3-uart-20261001-152024.jsonl", "M3 场景响应", "13 条变化快照，605 条接收帧，4 个独立提示事件；不含按键消抖或 HDMI 显示延迟。"),
        load_trace("diagnostics/timing-fix-board-physical-actions-com38.jsonl.gz", "时序修复后操作", "独立于 M5 长稳的另一轮历史采集；不合并为同一次验收。", 2),
    ]
    audit = json.loads((REPO / "diagnostics/m5-two-hour-audit-20261003.json").read_text())
    long = traces[0]
    assert long["records"] == audit["kinds"]["status"] == 143680
    assert long["raw_sha256"] == audit["raw_sha256"]
    assert long["index_changes"] == audit["index_changes"] == 2892
    assert long["fault_rows"] == 0 and long["summary"]["invalid"] == 0
    events = traces[1]["events"]
    assert len(events) == 4
    latencies = [event["internal_commit_ms"] for event in events]
    assert abs(sum(latencies) / 4 - 12.25702) < 1e-8
    cases = []
    def case(code, group, title, method, result, evidence, source, scope):
        cases.append(dict(id=code, group=group, title=title, method=method, result=result,
                          evidence=evidence, source=source, scope=scope))
    case("T01", "稳定性", "约两小时历史运行", "完整原始 JSONL 重新统计并核对 SHA-256", "143,680 条 / 7,198.516521 s", "原始日志核验", traces[0]["repository_source"], "历史 M5 版本；不是本次重新板测")
    case("T02", "稳定性", "UART 数据完整性", "检查原日志 summary 与 JSON 解码", "invalid=0；JSON 解码错误=0", "原始日志核验", traces[0]["repository_source"], "有效帧完整性，不代表物理链路零丢包")
    case("T03", "稳定性", "四图切换覆盖", "统计相邻快照 image_index 变化", "索引0/1/2/3；2,892次变化", "原始日志核验", traces[0]["repository_source"], "快照索引变化，不当作人工按键次数")
    case("T04", "稳定性", "存储故障观测", "统计 storage_fault_active", "故障记录 0", "原始日志核验", traces[0]["repository_source"], "只覆盖此历史采集窗口")
    case("T05", "事件响应", "提示场景提交延迟", "4次请求接受到片内 scene_commit", "9.58036～15.61504 ms；均值12.25702 ms", "原始日志核验", traces[1]["repository_source"], "n=4；不含消抖、网络和显示器延迟")
    case("T06", "事件响应", "修复后操作窗口", "独立 COM38 历史日志", "2,560条；1个事件=1.9022 ms", "原始日志核验", traces[2]["repository_source"], "另一版本和窗口；不并入4事件分布")
    case("T07", "图像与转场", "UI整帧比对", "独立参考模型生成9帧", "2,764,800像素；0 mismatch", "报告记载·仿真", "设计报告 表3-4；UI_V3_ACCEPTANCE_2026-10-05.md", "本次未重跑RTL仿真")
    case("T08", "图像与转场", "RGB→AXIS完整帧", "两帧逐像素检查", "960 EOL / 2 SOF", "报告记载·仿真", "设计报告 表3-4；tests/video_axis_tb.v", "历史仿真结果")
    case("T09", "图像与转场", "双完成握手", "3种完成顺序 × 2种接受时序", "6组组合通过", "报告记载·仿真", "设计报告 表3-4；tests/image_commit_tb.v", "历史仿真结果")
    case("T10", "图像与转场", "转场与高优先级抢占", "3阶段 × 2退出 × 2应答 × 启用/禁用", "24组组合；含负向对照", "报告记载·仿真", "设计报告 表3-4；E2_ACCEPTANCE.md", "与实板长稳分别列示")
    case("T11", "网络", "网页SPI写入预算", "2071 B，6.25 MHz，255 B突发", "10.60352 → 2.68544 ms", "理论计算复核", "设计报告 2.3 网络优化", "SPI线上传输预算；不是浏览器端到端实测")
    case("T12", "网络", "HTTP/UDP远程控制", "报告记载手机网页与协议专项", "5个专项；手机端可操作", "报告记载", "设计报告 表3-2 / 表3-4", "HTTP/UDP 控制功能记录，详见设计报告对应章节。")
    case("T13", "音画功能", "1024点实时FFT", "静音/单音/交叉/反相/重复性", "64频带定位与柱高符合预期", "报告记载", "设计报告 表3-4", "当前工程已集成实时 FFT 频谱模块；本项保留设计报告中的功能记录。")
    case("T14", "音画功能", "开屏流式播放", "3帧×307200字及无动画卡", "921,600字匹配；负向状态码", "报告记载", "设计报告 表3-4", "本次未获取对应新版原始波形")
    case("T15", "资源时序", "历史报告候选STA与资源", "TD路由后报告摘录", "+0.310 / +0.024 ns；LUT 14,676", "报告记载·构建", "设计报告 表3-3", "历史报告候选数据；当前提交版本指标见验证说明。")
    case("T16", "上位机", "历史版本桌面功能自动测试", "串口/CSV/坏帧/断线/UDP重传/Qt", "13项通过", "已有软件测试", "desktop/evidence/software-tests.json", "此前构建的软件验证；本次新增档案另测")
    case("T17", "上位机", "独立EXE与照片接收", "EXE启动 + UDP文件逐字节核对", "921,654 B BMP一致", "已有软件测试", "desktop/evidence/packaged/verification.json", "电脑接收服务，不等于FPGA照片接收")
    case("T18", "上位机", "另一台电脑运行确认", "用户于2026-11-01反馈", "已收到另一台电脑运行正常的反馈", "用户反馈", "本次对话 / 2026-11-01", "未提供设备型号、逐项步骤或独立串口日志")
    case("T19", "覆盖边界", "最新候选长稳与网络照片入板", "核对报告/仓库/历史记录的覆盖范围", "尚无本次新增实板证据", "待验证", "PROJECT_STATE.md；desktop/README.md", "保留待验证状态，不补造通过记录")
    extensions = extend_cases(cases)
    shutil.copyfile(ROOT / "evidence/report_source/paragraphs.json", OUT / "sources" / "设计报告段落摘录.json")
    for relative in ("diagnostics/m5-two-hour-audit-20261003.json", "diagnostics/m5-uart-metrics-20261002.json",
                     "diagnostics/timing-fix-board-physical-actions-audit.json", "M5_ACCEPTANCE.md"):
        shutil.copyfile(REPO / relative, OUT / "sources" / Path(relative).name)
    for relative in ("evidence/software-tests.json", "evidence/packaged/verification.json"):
        shutil.copyfile(ROOT / relative, OUT / "sources" / ("desktop-" + Path(relative).name))
    manifest = {"schema": 1, "title": "红色数字展馆 · 测试档案", "team": "瞬应逻辑队",
                "assembled_date": "2026-11-01", "report": report, "cases": cases, "traces": traces,
                "extensions": extensions,
                "latency": {"n": 4, "values_ms": latencies, "mean_ms": sum(latencies) / 4,
                            "min_ms": min(latencies), "max_ms": max(latencies)},
                "network_budget": {"before_ms": 2071 * 32 / 6250000 * 1000,
                                   "after_ms": (2071 * 8 + 9 * 24) / 6250000 * 1000},
                "sources": {p.name: digest(p) for p in (OUT / "sources").iterdir() if p.is_file()}}
    (OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    with (OUT / "测试用例与证据.csv").open("w", newline="", encoding="utf-8-sig") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(cases[0]))
        writer.writeheader()
        writer.writerows(cases)
    print(json.dumps({"cases": len(cases), "historical_records": sum(t["records"] for t in traces),
                      "long_run_hash_verified": True, "latency_samples": latencies,
                      "output": str(OUT)}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    # The submission already contains the historical archive. Refresh its current
    # capture without relying on paths that existed only in the development repo.
    if (REPO / 'datasets/measured/long-run-72h-20261028-1031/test-summary.json').is_file():
        import runpy
        runpy.run_path(str(REPO / 'tools/sync_long_run_archive.py'), run_name='__main__')
    else:
        main()
