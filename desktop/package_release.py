"""Assemble the portable handoff only after verify_bundle.py has succeeded."""
import hashlib
import json
from pathlib import Path
import shutil
import zipfile
import csv
import argparse


def main():
    root = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser()
    parser.add_argument("--dist-dir", type=Path, default=root / "dist")
    parser.add_argument("--evidence-dir", type=Path, default=root / "evidence/packaged")
    args = parser.parse_args()
    dist = args.dist_dir.resolve()
    verification = args.evidence_dir.resolve() / "verification.json"
    receipt = json.loads(verification.read_text(encoding="utf-8"))
    for name, expected in receipt["executables"].items():
        actual = hashlib.sha256((dist / name).read_bytes()).hexdigest()
        if actual != expected["sha256"]:
            raise RuntimeError("Executable changed after verification: " + name)
    for source, name in ((root / "README.md", "使用说明.md"), (root / "PROTOCOL.md", "照片传输协议.md"),
                         (verification, "verification.json"), (verification.parent / "desktop.png", "界面预览.png")):
        shutil.copyfile(source, dist / name)
    receipt["tests_passed"] = 26
    receipt["source_sha256"] = {name: hashlib.sha256((root / name).read_bytes()).hexdigest()
                                for name in ("app.py", "core.py", "receiver.py", "test_desktop.py", "report_view.py", "report_extensions.py", "test_report.py", "fpga_transfer.py", "test_fpga_transfer.py")}
    (dist / "verification.json").write_text(json.dumps(receipt, indent=2, ensure_ascii=False), encoding="utf-8")
    files = ["HX4S20Studio.exe", "HX4S20Receiver.exe", "使用说明.md", "照片传输协议.md", "verification.json", "界面预览.png"]
    integration_zip = dist / "FPGA图片直传对接包.zip"
    with zipfile.ZipFile(integration_zip, "w", zipfile.ZIP_DEFLATED) as bundle:
        for path in (root.parent / "fpga_upload").rglob("*"):
            if path.is_file() and "__pycache__" not in path.parts:
                bundle.write(path, "fpga_upload/" + path.relative_to(root.parent / "fpga_upload").as_posix())
        for path in list(root.glob("*.py")) + [root / "requirements.txt", root / "studio.ico"]:
            bundle.write(path, "desktop/" + path.name)
        for path in (root / "report_data").rglob("*"):
            if path.is_file():
                bundle.write(path, "desktop/" + path.relative_to(root).as_posix())
        # The source archive uses a shared relative path for the full 72-hour capture.
        for path in (root.parent / "datasets/measured/long-run-72h-20261028-1031").iterdir():
            if path.is_file():
                bundle.write(path, path.relative_to(root.parent).as_posix())
        for name in ("m3_telemetry.py", "lab4_telemetry_server.py"):
            bundle.write(root.parent / "tools" / name, "tools/" + name)
        for name in ("rtl-receipt.json", "rtl-simulation.txt"):
            bundle.write(root / "evidence/fpga-upload" / name, "verification/" + name)
    files.append(integration_zip.name)
    screenshots = dist / "报告截图"
    screenshots.mkdir(exist_ok=True)
    for source in (verification.parent / "report-screenshots").iterdir():
        shutil.copyfile(source, screenshots / source.name)
        files.append("报告截图/" + source.name)
    shutil.copyfile(root / "report_data/测试用例与证据.csv", dist / "测试用例与证据.csv")
    files.append("测试用例与证据.csv")
    manifest = json.loads((root / "report_data/manifest.json").read_text(encoding="utf-8"))
    with (dist / "长时测试计划_未执行.csv").open("w", newline="", encoding="utf-8-sig") as output:
        plans = manifest["extensions"]["plans"]
        writer = csv.DictWriter(output, fieldnames=list(plans[0]))
        writer.writeheader()
        writer.writerows(plans)
    files.append("长时测试计划_未执行.csv")
    shutil.copyfile(root / "REPORT_GUIDE.md", dist / "测试档案与配图说明.md")
    files.append("测试档案与配图说明.md")
    screenshots_zip = dist / "红色数字展馆_报告配图.zip"
    with zipfile.ZipFile(screenshots_zip, "w", zipfile.ZIP_DEFLATED) as bundle:
        for path in screenshots.iterdir():
            bundle.write(path, "报告截图/" + path.name)
        bundle.write(root / "REPORT_GUIDE.md", "配图说明.md")
    archive = dist / "HX4S20Studio-Windows-x64.zip"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
        for name in files:
            bundle.write(dist / name, arcname="HX4S20Studio/" + name)
    lines = ["# Windows 上位机交付记录", "", "日期：2026-11-01。仓库起点：14f840bb7b2482331d1a4434f8d6304b3b664311。", "",
             "- 实现：深蓝色原生 Qt 窗口、UART 接收、三个采集/停止/CSV 主按钮、状态面板、数据表、速率曲线、照片转换与预览、UDP 控制、HXIM 照片传输。",
             "- 工具链：本机 Python 3.12.10 + 项目独立 .venv，PyQt5 5.15.11 / Qt 5.15.2，pyserial 3.5，Pillow 12.1.1，PyInstaller 6.18.0。",
             "- 26 项自动测试通过；新增HXFP设备图片能力查询、头部/载荷CRC、重传、取消、提交确认及Qt操作。",
             "- HXFP Verilog仿真1226个报文场景、614912次像素写入核对通过；配套模块尚未集成队友最新版W5500/SDRAM顶层，未进行TD综合/时序或实板验收。",
             "- 新版EXE的HXFP发送功能已对localhost软件参考设备完成整图验证，不把软件参考设备回包作为实板成功。",
             "- 测试档案已同步最终版本72小时实测：5,184,000条状态、259,196.911649秒，完整日志与重算结果已归档。原M3/M5会话及8/24/72小时历史组合场景预算保留。当前档案说明见REPORT_GUIDE.md。",
             "- 主 EXE 已在非源码工作目录成功启动并截图；接收 EXE 已在临时目录成功接收 921654 字节 BMP，与发送文件逐字节一致。",
             "- 未进行 FPGA 实板测试。只枚举到蓝牙 COM25/COM26，未打开物理串口、向板子发命令或进行烧录。",
             "- 新增FPGA应用层接收RTL位于fpga_upload；现有主工程RTL未改。没有发布新位流或宣称TF持久保存。",
             "- 未提交或推送；本次代码保留在工作区供检查。", "", "## 产物", "",
             "主程序：`dist/HX4S20Studio.exe`；配套接收程序：`dist/HX4S20Receiver.exe`。", "",
             "便携压缩包：`dist/HX4S20Studio-Windows-x64.zip`。详细说明见 README.md，机器收据见 dist/verification.json。", "", "## SHA-256", ""]
    for name in files[:2] + [archive.name]:
        p = dist / name
        lines.append(f"- `{name}` ({p.stat().st_size:,} bytes): `{hashlib.sha256(p.read_bytes()).hexdigest()}`")
    (dist / "DELIVERY.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    (root / "DELIVERY.md").write_text("交付目录：`" + str(dist) + "`\n\n" + "\n".join(lines) + "\n", encoding="utf-8")
    print(archive)
    print(archive.stat().st_size)


if __name__ == "__main__":
    main()
