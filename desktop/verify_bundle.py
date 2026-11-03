"""Verify the delivered EXEs, without opening physical serial ports or targeting a board."""
import hashlib
import argparse
import json
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import threading
import unittest

from core import upload_image
from test_desktop import bmp
from fpga_reference import ReferenceDevice
from fpga_transfer import encode_rgb565


def main():
    root = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser()
    parser.add_argument("--dist-dir", type=Path, default=root / "dist")
    parser.add_argument("--evidence-dir", type=Path, default=root / "evidence/packaged")
    args = parser.parse_args()
    evidence = args.evidence_dir.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    studio = args.dist_dir.resolve() / "HX4S20Studio.exe"
    receiver = args.dist_dir.resolve() / "HX4S20Receiver.exe"
    result = subprocess.run([str(studio), "--smoke-test", str(evidence)], cwd=evidence, timeout=90, creationflags=subprocess.CREATE_NO_WINDOW)
    if result.returncode:
        raise RuntimeError(f"Packaged GUI failed: {result.returncode}")
    startup = json.loads((evidence / "startup.json").read_text(encoding="utf-8"))
    assert startup["ok"] and not startup["hardware_opened"]
    capture_dir = evidence / "report-screenshots"
    result = subprocess.run([str(studio), "--report-capture", str(capture_dir)], cwd=evidence,
                            timeout=90, creationflags=subprocess.CREATE_NO_WINDOW)
    if result.returncode:
        raise RuntimeError("Packaged report capture failed")
    capture_receipt = json.loads((capture_dir / "截图收据.json").read_text(encoding="utf-8"))
    assert capture_receipt["packaged_executable"] and len(capture_receipt["pages"]) == 6
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    with tempfile.TemporaryDirectory() as temp, (evidence / "receiver.txt").open("w", encoding="utf-8") as log:
        proc = subprocess.Popen([str(receiver), "--host", "127.0.0.1", "--port", str(port), "--output", temp], cwd=temp, stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            deadline = time.monotonic() + 60
            while "Listening UDP" not in (evidence / "receiver.txt").read_text(encoding="utf-8", errors="replace"):
                if proc.poll() is not None or time.monotonic() > deadline:
                    raise RuntimeError("Packaged receiver did not start")
                time.sleep(0.1)
            data = bmp()
            digest = upload_image("127.0.0.1", port, data, "bundle-test.bmp")
            files = list(Path(temp).glob("*.bmp"))
            assert len(files) == 1 and files[0].read_bytes() == data
        finally:
            # PyInstaller onefile has a bootloader parent and an application child.
            # Close only the process tree launched by this test.
            if proc.poll() is None:
                subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"], capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW)
            proc.wait(timeout=10)
    # Exercise the actual packaged sender against an independent localhost model.
    # This is software protocol verification, not FPGA board validation.
    model = ReferenceDevice()
    stop = threading.Event()
    server = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    server.bind(("127.0.0.1", 0))
    server.settimeout(0.1)
    model_port = server.getsockname()[1]
    errors = []
    def serve_model():
        try:
            while not stop.is_set():
                try:
                    raw, peer = server.recvfrom(2048)
                except socket.timeout:
                    continue
                reply = model.handle(raw, peer)
                if reply:
                    server.sendto(reply, peer)
        except Exception as exc:
            errors.append(str(exc))
    thread = threading.Thread(target=serve_model)
    thread.start()
    try:
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / "test.bmp"
            source.write_bytes(bmp())
            result = subprocess.run([str(studio), "--send-image", str(source), "--device-ip", "127.0.0.1",
                                     "--image-port", str(model_port), "--transfer-records", temp],
                                    cwd=temp, timeout=90, creationflags=subprocess.CREATE_NO_WINDOW)
            if result.returncode:
                raise RuntimeError("Packaged HXFP sender failed")
            transfer = json.loads(next(Path(temp).glob("*.json")).read_text(encoding="utf-8"))
            assert transfer["display_confirmed"] and model.displayed == 1
            assert bytes(model.data) == encode_rgb565(bmp())
            (evidence / "hxfp-model-transfer.json").write_text(json.dumps({"test_endpoint": "localhost software reference", **transfer}, indent=2), encoding="utf-8")
    finally:
        stop.set()
        thread.join(2)
        server.close()
    assert not errors
    receipt = {
        "gui_startup": "passed", "packaged_receiver_udp_transfer": "passed",
        "transferred_bytes": len(data), "image_sha256": digest,
        "physical_uart_opened": False, "fpga_hardware_validated": False,
        "report_pages_captured": capture_receipt["pages"],
        "software_tests_discovered": unittest.defaultTestLoader.loadTestsFromNames(
            ["test_desktop", "test_report", "test_fpga_transfer"]).countTestCases(),
        "packaged_hxfp_sender_to_software_model": "passed", "hxfp_pixels_verified": 307200,
        "executables": {p.name: {"bytes": p.stat().st_size, "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in (studio, receiver)},
    }
    (evidence / "verification.json").write_text(json.dumps(receipt, indent=2), encoding="utf-8")
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
