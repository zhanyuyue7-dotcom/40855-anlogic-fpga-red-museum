import csv
import hashlib
import io
import json
import os
from pathlib import Path
import socket
import struct
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

from PIL import Image

from core import (ACK, DATA, FINISH, HELLO, ImageReceiver, SessionStore, TelemetryDecoder,
                  TransferCancelled, command_packet, image_packet, prepare_image,
                  unpack_image_packet, upload_image)


def telemetry(version=3):
    packet = bytearray(24 if version == 1 else 64)
    packet[:6] = bytes((0xA5, 0x33, version, 1, 2, 1))
    struct.pack_into("<IIII", packet, 6, 5, 1, 4, 25000)
    packet[22] = 1
    if version >= 2:
        packet[23:28] = bytes((1, 4, 2, 2, 0x65))
    if version == 3:
        packet[60] = 11
    for b in packet[:-1]:
        packet[-1] ^= b
    return bytes(packet)


def bmp():
    stream = io.BytesIO()
    Image.new("RGB", (640, 480), (25, 100, 200)).save(stream, format="BMP")
    return stream.getvalue()


class ProtocolTests(unittest.TestCase):
    def test_command_reference_vector(self):
        # Independent CRC-8/SMBUS check vector + fixed frame checked against RTL polynomial.
        packet = command_packet(0x10, 1)
        self.assertEqual(packet[:7], bytes.fromhex("a5 01 01 10 00 00 00"))
        dividend = int.from_bytes(packet, "big")
        for bit in range(63, 7, -1):
            if dividend & (1 << bit):
                dividend ^= 0x107 << (bit - 8)
        self.assertEqual(dividend, 0)
        with self.assertRaises(ValueError):
            command_packet(0x20, 0)

    def test_uart_all_versions_bytewise_and_resync(self):
        for version in (1, 2, 3):
            decoder = TelemetryDecoder()
            packet = telemetry(version)
            bad = bytearray(packet)
            bad[-1] ^= 0x80
            records = []
            for byte in b"noise" + bad + packet + packet:
                records.extend(decoder.feed(bytes([byte])))
            self.assertEqual(len(records), 2)
            self.assertEqual(records[0]["scene_id"], 1)
            self.assertEqual(records[0]["internal_commit_ms"], 1)
            self.assertGreater(decoder.invalid, 0)
            if version == 3:
                self.assertEqual(records[0]["brightness_percent"], 100)
                self.assertTrue(records[0]["audio_enabled"])

    def test_lab4_and_bounded_noise(self):
        decoder = TelemetryDecoder()
        self.assertFalse(decoder.feed(b"@S,1,4,2,1,0,"))
        records = decoder.feed(b"1,1,1,0,1\r\n")
        self.assertEqual(records[0]["image_index"], 2)
        self.assertTrue(records[0]["auto_play"])
        decoder.feed(b"z" * 100000)
        self.assertLessEqual(len(decoder.lines), 4096)

    def test_raw_hex(self):
        records = TelemetryDecoder("原始 HEX").feed(b"\xff\x00\xa5")
        self.assertEqual(records[0]["raw_hex"], "ff 00 a5")

    def test_csv_retains_every_record_and_utf8_bom(self):
        with tempfile.TemporaryDirectory() as temp:
            store = SessionStore(Path(temp) / "capture.sqlite3")
            store.append([{"timestamp": "2026-11-01T12:00:00+08:00", "protocol": "M3", "scene_id": i, "note": "中文,换行\n保留"} for i in range(1001)])
            store.append([{"timestamp": "t", "protocol": "HEX", "raw_hex": "ff 00", "note": "=1+1"}])
            path = Path(temp) / "result.csv"
            self.assertEqual(store.export_csv(path), 1002)
            self.assertTrue(path.read_bytes().startswith(b"\xef\xbb\xbf"))
            with path.open(encoding="utf-8-sig", newline="") as file:
                rows = list(csv.DictReader(file))
            self.assertEqual(rows[1000]["scene_id"], "1000")
            self.assertEqual(rows[0]["note"], "中文,换行\n保留")
            self.assertEqual(rows[-1]["note"], "'=1+1")

    def test_image_conversion_header_and_aspect(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "portrait.png"
            Image.new("RGB", (50, 100), "red").save(path)
            data = prepare_image(path)
            self.assertEqual(data[:2], b"BM")
            self.assertEqual(struct.unpack_from("<ii", data, 18), (640, 480))
            self.assertEqual(struct.unpack_from("<H", data, 28)[0], 24)
            self.assertEqual(struct.unpack_from("<I", data, 30)[0], 0)
            with Image.open(io.BytesIO(data)) as image:
                self.assertEqual(image.getpixel((0, 0)), (0, 0, 0))
                self.assertEqual(image.getpixel((320, 240)), (255, 0, 0))

    def test_udp_end_to_end_with_lost_ack_and_final_ack(self):
        with tempfile.TemporaryDirectory() as temp:
            receiver = ImageReceiver(temp)
            server = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            server.bind(("127.0.0.1", 0))
            server.settimeout(0.1)
            port = server.getsockname()[1]
            stop = threading.Event()
            dropped = set()

            def serve():
                while not stop.is_set():
                    try:
                        packet, peer = server.recvfrom(4096)
                    except socket.timeout:
                        continue
                    kind, _, sequence, _ = unpack_image_packet(packet)
                    reply = receiver.handle(packet, peer)
                    if kind in (HELLO, FINISH) or (kind == DATA and sequence == 2):
                        if kind not in dropped:
                            dropped.add(kind)
                            continue
                    if reply:
                        server.sendto(reply, peer)

            thread = threading.Thread(target=serve)
            thread.start()
            data = bmp()
            try:
                digest = upload_image("127.0.0.1", port, data, "../../unsafe.bmp", timeout=0.04)
                self.assertEqual(digest, hashlib.sha256(data).hexdigest())
            finally:
                stop.set()
                thread.join(2)
                server.close()
            files = list(Path(temp).glob("*.bmp"))
            self.assertEqual(len(files), 1)
            self.assertEqual(files[0].read_bytes(), data)
            self.assertEqual(dropped, {HELLO, DATA, FINISH})

    def test_upload_timeout_and_cancel(self):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as blackhole:
            blackhole.bind(("127.0.0.1", 0))
            with self.assertRaises(TimeoutError):
                upload_image("127.0.0.1", blackhole.getsockname()[1], b"abc", "x.bmp", timeout=0.01, retries=2)
            stop = threading.Event()
            stop.set()
            with self.assertRaises(TransferCancelled):
                upload_image("127.0.0.1", blackhole.getsockname()[1], b"abc", "x.bmp", cancel=stop)

    def test_receiver_rejects_corruption_and_incomplete_file(self):
        with tempfile.TemporaryDirectory() as temp:
            receiver = ImageReceiver(temp)
            peer = ("127.0.0.1", 1234)
            metadata = json.dumps({"size": 12, "sha256": "0" * 64}).encode()
            self.assertEqual(unpack_image_packet(receiver.handle(image_packet(HELLO, 1, 0, metadata), peer))[0], ACK)
            corrupt = image_packet(DATA, 1, 1, b"abc")[:-1] + b"x"
            self.assertIsNone(receiver.handle(corrupt, peer))
            self.assertEqual(unpack_image_packet(receiver.handle(image_packet(FINISH, 1, 1), peer))[0], 129)
            self.assertFalse(list(Path(temp).glob("*.bmp")))


class GuiTests(unittest.TestCase):
    def setUp(self):
        from PyQt5.QtCore import QSettings
        self.settings_temp = tempfile.TemporaryDirectory()
        self.settings_patch = patch("app.QSettings", return_value=QSettings(str(Path(self.settings_temp.name) / "test.ini"), QSettings.IniFormat))
        self.settings_patch.start()

    def tearDown(self):
        self.settings_patch.stop()
        self.settings_temp.cleanup()

    @classmethod
    def setUpClass(cls):
        from PyQt5.QtWidgets import QApplication
        cls.app = QApplication.instance() or QApplication([])

    def pump_until(self, condition, seconds=4):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            self.app.processEvents()
            if condition():
                return
            time.sleep(0.01)
        self.fail("Qt condition timed out")

    def test_gui_capture_stop_export_and_photo_mode(self):
        from app import MainWindow

        class FakeSerial:
            def __init__(self):
                self.sent = False
            def __enter__(self):
                return self
            def __exit__(self, *_):
                pass
            @property
            def in_waiting(self):
                return 128 if not self.sent else 0
            def read(self, _):
                time.sleep(0.01)
                if not self.sent:
                    self.sent = True
                    return telemetry(3) * 2
                return b""

        with tempfile.TemporaryDirectory() as temp, patch("app.data_directory", return_value=Path(temp)), patch("app.serial.serial_for_url", return_value=FakeSerial()):
            window = MainWindow()
            window.port.addItem("Test UART", "test://")
            window.port.setCurrentIndex(window.port.count() - 1)
            window.start_capture()
            self.pump_until(lambda: window.record_count == 2)
            self.assertFalse(window.start_button.isEnabled())
            self.assertEqual(window.metrics["scene"].text(), "提示")
            window.stop_capture()
            self.pump_until(lambda: window.capture is None)
            self.assertTrue(window.start_button.isEnabled())
            self.assertFalse(window.stop_button.isEnabled())
            self.assertTrue(window.export_button.isEnabled())
            self.assertEqual(window.store.count(), 2)
            self.assertEqual(window.store.path.with_suffix(".raw.bin").read_bytes(), telemetry(3) * 2)
            output = str(Path(temp) / "gui.csv")
            with patch("app.QFileDialog.getSaveFileName", return_value=(output, "CSV")):
                window.export_csv()
            self.pump_until(lambda: window.exporter is None)
            self.assertTrue(Path(output).exists())
            path = Path(temp) / "photo.bmp"
            path.write_bytes(bmp())
            window.image_path = path
            window.profile.setCurrentIndex(0)  # Legacy firmware must not offer photo upload.
            window.reprepare_image()
            self.assertFalse(window.upload_button.isEnabled())
            window.profile.setCurrentIndex(1)
            self.assertTrue(window.upload_button.isEnabled())
            self.assertFalse(window.control_buttons[0].isEnabled())
            window.close()

    def test_serial_open_failure_restores_controls(self):
        from app import MainWindow
        with tempfile.TemporaryDirectory() as temp, patch("app.data_directory", return_value=Path(temp)), patch("app.serial.serial_for_url", side_effect=OSError("Port busy")):
            window = MainWindow()
            window.port.addItem("Test UART", "test://")
            window.port.setCurrentIndex(window.port.count() - 1)
            window.start_capture()
            self.pump_until(lambda: window.capture is None)
            self.assertTrue(window.start_button.isEnabled())
            self.assertIn("异常", window.badge.text())
            self.assertFalse(window.export_button.isEnabled())
            window.close()

    def test_disconnect_preserves_last_partial_batch(self):
        from app import CaptureWorker

        class DisconnectingSerial:
            def __init__(self):
                self.sent = False
            def __enter__(self):
                return self
            def __exit__(self, *_):
                pass
            @property
            def in_waiting(self):
                return 64
            def read(self, _):
                if self.sent:
                    raise OSError("device unplugged")
                self.sent = True
                return telemetry(3)

        with tempfile.TemporaryDirectory() as temp, patch("app.serial.serial_for_url", return_value=DisconnectingSerial()):
            store = SessionStore(Path(temp) / "disconnect.sqlite3")
            worker = CaptureWorker("test://", 115200, "自动识别", store)
            worker.start()
            self.pump_until(lambda: not worker.isRunning())
            self.assertEqual(store.count(), 1)
            self.assertEqual(store.path.with_suffix(".raw.bin").read_bytes(), telemetry(3))

    def test_gui_upload_and_network_command_loopback(self):
        from app import MainWindow
        with tempfile.TemporaryDirectory() as temp:
            receiver = ImageReceiver(Path(temp) / "received")
            stop = threading.Event()
            ready = threading.Event()
            address = []
            def on_ready(addr):
                address.append(addr)
                ready.set()
            thread = threading.Thread(target=receiver.serve, args=("127.0.0.1", 0, stop, on_ready))
            thread.start()
            self.assertTrue(ready.wait(2))
            window = MainWindow()
            original_host, original_port = window.host.text(), window.netport.value()
            try:
                window.host.setText("127.0.0.1")
                with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as command_sink:
                    command_sink.bind(("127.0.0.1", 0))
                    command_sink.settimeout(1)
                    window.netport.setValue(command_sink.getsockname()[1])
                    window.send_command(0x10, "下一张")
                    self.assertEqual(command_sink.recv(100), command_packet(0x10, 0))
                window.netport.setValue(address[0][1])
                window.profile.setCurrentIndex(1)
                path = Path(temp) / "image.bmp"
                path.write_bytes(bmp())
                window.image_path = path
                window.reprepare_image()
                window.start_upload()
                self.assertFalse(window.choose_button.isEnabled())
                self.pump_until(lambda: window.upload is None, seconds=10)
                self.assertEqual(window.progress.value(), 100)
                self.assertIn("接收端已校验", window.transfer_note.text())
                self.assertEqual(len(list((Path(temp) / "received").glob("*.bmp"))), 1)
            finally:
                stop.set()
                thread.join(2)
                window.host.setText(original_host)
                window.netport.setValue(original_port)
                window.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
