import contextlib
import io
import json
from pathlib import Path
import socket
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
import zlib

from PIL import Image
from fpga_transfer import (DeviceClient, DeviceError, upload_to_fpga, encode_rgb565, packet, unpack,
                           PROBE, BEGIN, DATA, COMMIT, ABORT, RESPONSE, DeviceStatus)
from fpga_reference import ReferenceDevice
from core import TransferCancelled


def image_bmp():
    im = Image.new("RGB", (640,480), "#b73163")
    im.putpixel((0,0),(255,0,0))
    im.putpixel((639,479),(0,0,255))
    output=io.BytesIO(); im.save(output,format="BMP")
    return output.getvalue()


class Server:
    def __init__(self, drop=False, mutate=None):
        self.device=ReferenceDevice()
        self.sock=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
        self.sock.bind(("127.0.0.1",0));self.sock.settimeout(.05)
        self.port=self.sock.getsockname()[1]
        self.stop=threading.Event()
        self.drop=drop;self.mutate=mutate;self.dropped=set();self.ops=[]
        self.errors=[]
        self.thread=threading.Thread(target=self.serve)

    def serve(self):
        try:
            while not self.stop.is_set():
                try: raw,peer=self.sock.recvfrom(2048)
                except socket.timeout: continue
                op,session,seq,body=unpack(raw)
                self.ops.append(op)
                reply=self.device.handle(raw,peer)
                if self.drop and (op in (BEGIN,COMMIT) or (op==DATA and seq==2)) and op not in self.dropped:
                    self.dropped.add(op);continue
                if self.mutate: reply=self.mutate(op,session,seq,reply)
                if reply: self.sock.sendto(reply,peer)
        except Exception as exc:
            self.errors.append(exc)

    def __enter__(self):
        self.thread.start();return self

    def __exit__(self,*_):
        self.stop.set();self.thread.join(2);self.sock.close()
        if self.errors: raise self.errors[0]


class FpgaTransferTests(unittest.TestCase):
    def test_pixel_format_orientation(self):
        data=encode_rgb565(image_bmp())
        self.assertEqual(len(data),614400)
        self.assertEqual(data[:2],b"\x00\xf8")
        self.assertEqual(data[-2:],b"\x1f\x00")

    def test_packet_crc_protects_header_and_body(self):
        raw=packet(DATA,123,9,b"\x12\x34")
        self.assertEqual(unpack(raw),(DATA,123,9,b"\x12\x34"))
        for offset in (5,6,10,14,16,21):
            bad=bytearray(raw);bad[offset]^=1
            with self.assertRaises(ValueError): unpack(bytes(bad))

    def test_full_upload_lost_ack_is_idempotent(self):
        with tempfile.TemporaryDirectory() as temp, Server(drop=True) as server:
            data=image_bmp()
            result=upload_to_fpga("127.0.0.1",server.port,data,"photo.bmp",receipt_dir=temp,timeout=.08)
            self.assertTrue(result["display_confirmed"])
            self.assertEqual(result["bytes_confirmed"],614400)
            self.assertEqual(result["retransmissions"],3)
            self.assertEqual(bytes(server.device.data),encode_rgb565(data))
            self.assertEqual(server.device.displayed,1)
            self.assertEqual(len(server.device.writes),307200)
            self.assertTrue(Path(result["receipt_path"]).exists())

    def test_wrong_ack_session_or_crc_ignored(self):
        attempts=[0]
        def mutate(op,sid,seq,reply):
            if op==PROBE:
                attempts[0]+=1
                if attempts[0]==1:
                    kind,_,_,body=unpack(reply)
                    return packet(kind,sid+1,seq,body)
                if attempts[0]==2:
                    return reply[:-1]+bytes([reply[-1]^1])
            return reply
        with Server(mutate=mutate) as server, DeviceClient("127.0.0.1",server.port,timeout=.02) as client:
            self.assertEqual(client.probe().width,640)
            self.assertEqual(client.retransmissions,2)

    def test_missing_interface_does_not_send_image(self):
        with tempfile.TemporaryDirectory() as temp, Server(mutate=lambda *args:None) as server:
            with self.assertRaises(TimeoutError):
                upload_to_fpga("127.0.0.1",server.port,image_bmp(),"x",receipt_dir=temp,timeout=.02,retries=2,commit_timeout=.02)
            self.assertEqual(set(server.ops),{PROBE})
            receipt=json.loads(next(Path(temp).glob("*.json")).read_text(encoding="utf-8"))
            self.assertFalse(receipt["display_confirmed"])

    def test_cancel_aborts_staged_image(self):
        stop=threading.Event()
        with tempfile.TemporaryDirectory() as temp, Server() as server:
            with self.assertRaises(TransferCancelled):
                upload_to_fpga("127.0.0.1",server.port,image_bmp(),"x",receipt_dir=temp,cancel=stop,
                               progress=lambda n,t:stop.set() if n>=2048 else None,timeout=.03)
            self.assertFalse(server.device.active)
            self.assertEqual(server.device.displayed,0)
            receipt=json.loads(next(Path(temp).glob("*.json")).read_text(encoding="utf-8"))
            self.assertTrue(receipt["abort_confirmed"])

    def test_commit_never_acknowledged_is_unknown_not_success(self):
        def mutate(op,sid,seq,reply):
            return None if op==COMMIT else reply
        with tempfile.TemporaryDirectory() as temp, Server(mutate=mutate) as server:
            with self.assertRaises(TimeoutError):
                upload_to_fpga("127.0.0.1",server.port,image_bmp(),"x",receipt_dir=temp,timeout=.02,retries=2,commit_timeout=.02)
            receipt=json.loads(next(Path(temp).glob("*.json")).read_text(encoding="utf-8"))
            self.assertEqual(receipt["status"],"commit_result_unknown")
            self.assertFalse(receipt["display_confirmed"])
            self.assertNotIn(ABORT,server.ops)

    def test_display_commit_has_independent_wait_budget(self):
        def delayed_commit(op,sid,seq,reply):
            if op == COMMIT:
                time.sleep(.12)  # SDRAM drain/display commit exceeds a data ACK deadline.
            return reply
        with tempfile.TemporaryDirectory() as temp, Server(mutate=delayed_commit) as server:
            result=upload_to_fpga("127.0.0.1",server.port,image_bmp(),"x",receipt_dir=temp,
                                  timeout=.04,retries=2,commit_timeout=.3)
            self.assertTrue(result["display_confirmed"])
            self.assertTrue(result["commit_requested"])
            self.assertEqual(server.ops.count(COMMIT),1)
            self.assertEqual(server.device.displayed,1)
            self.assertGreaterEqual(result["elapsed_seconds"]-result["pixels_confirmed_elapsed_s"],.1)

    def test_invalid_transfer_budgets_rejected(self):
        for timeout,retries in ((0,6),(-1,6),(float('nan'),6),(.1,0),(.1,1.5)):
            with self.assertRaises(ValueError):
                DeviceClient("127.0.0.1",timeout=timeout,retries=retries)
        with self.assertRaises(ValueError):
            upload_to_fpga("127.0.0.1",5002,image_bmp(),"x",commit_timeout=0)

    def test_nonempty_begin_crc_is_rejected_before_pixels(self):
        def bad_begin(op,sid,seq,reply):
            if op == BEGIN:
                kind,_,_,body=unpack(reply)
                status,phase,chunk,count,crc,dim=RESPONSE.unpack(body)
                return packet(kind,sid,seq,RESPONSE.pack(status,phase,chunk,count,1,dim))
            return reply
        with tempfile.TemporaryDirectory() as temp, Server(mutate=bad_begin) as server:
            with self.assertRaises(DeviceError):
                upload_to_fpga("127.0.0.1",server.port,image_bmp(),"x",receipt_dir=temp)
            self.assertNotIn(DATA,server.ops)
            self.assertFalse(server.device.active)

    def test_gui_waits_at_99_until_display_ack(self):
        from PyQt5.QtWidgets import QApplication
        from PyQt5.QtCore import QSettings
        from app import MainWindow
        app=QApplication.instance() or QApplication([])
        commit_arrived=threading.Event()
        release_ack=threading.Event()
        def hold_commit(op,sid,seq,reply):
            if op == COMMIT:
                commit_arrived.set()
                release_ack.wait(2)
            return reply
        def pump(predicate):
            until=time.monotonic()+10
            while time.monotonic()<until:
                app.processEvents()
                if predicate(): return
                time.sleep(.005)
            self.fail("UI timeout")
        with tempfile.TemporaryDirectory() as temp, Server(mutate=hold_commit) as server, patch("fpga_transfer.data_directory",return_value=Path(temp)):
            win=MainWindow(settings=QSettings(str(Path(temp)/"test.ini"),QSettings.IniFormat))
            win.host.setText("127.0.0.1"); win.image_port.setValue(server.port)
            path=Path(temp)/"photo.bmp"; path.write_bytes(image_bmp())
            win.image_path=path; win.reprepare_image()
            try:
                win.start_upload()
                pump(lambda: commit_arrived.is_set() and not win.cancel_button.isEnabled())
                self.assertEqual(win.progress.value(),99)
                self.assertIn("显示提交",win.transfer_note.text())
                self.assertFalse(win.commit_wait.isEnabled())
            finally:
                release_ack.set()
                pump(lambda: win.upload is None)
                win.close()
            self.assertEqual(win.progress.value(),100)

    def test_ack_wrong_offset_stops_upload(self):
        def mutate(op,sid,seq,reply):
            if op==DATA:
                kind,_,_,body=unpack(reply)
                status,phase,chunk,count,crc,dim=RESPONSE.unpack(body)
                return packet(kind,sid,seq,RESPONSE.pack(status,phase,chunk,count+2,crc,dim))
            return reply
        with tempfile.TemporaryDirectory() as temp,Server(mutate=mutate) as server:
            with self.assertRaises(DeviceError):
                upload_to_fpga("127.0.0.1",server.port,image_bmp(),"x",receipt_dir=temp,timeout=.03)
            self.assertEqual(server.device.displayed,0)
            self.assertFalse(server.device.active)

    def test_gui_probe_and_upload_device_profile(self):
        from PyQt5.QtWidgets import QApplication
        from app import MainWindow
        app=QApplication.instance() or QApplication([])
        def wait_for(predicate):
            until=time.monotonic()+10
            while time.monotonic()<until:
                app.processEvents()
                if predicate():return
                time.sleep(.005)
            self.fail("UI timeout")
        with tempfile.TemporaryDirectory() as temp,Server() as server,patch("fpga_transfer.data_directory",return_value=Path(temp)):
            from PyQt5.QtCore import QSettings
            win=MainWindow(settings=QSettings(str(Path(temp)/"test.ini"),QSettings.IniFormat))
            original_host,original_port=win.host.text(),win.image_port.value()
            win.host.setText("127.0.0.1");win.image_port.setValue(server.port)
            self.assertEqual(win.profile.currentIndex(),2)
            win.probe_fpga()
            wait_for(lambda:win.device_probe is None)
            self.assertIn("设备支持HXFP",win.network_note.text())
            path=Path(temp)/"photo.bmp";path.write_bytes(image_bmp())
            win.image_path=path;win.reprepare_image()
            self.assertTrue(win.upload_button.isEnabled())
            win.start_upload()
            wait_for(lambda:win.upload is None)
            self.assertEqual(win.progress.value(),100)
            self.assertIn("设备已确认显示提交",win.transfer_note.text())
            self.assertEqual(server.device.displayed,1)
            win.host.setText(original_host);win.image_port.setValue(original_port)
            win.close()


if __name__=="__main__":
    unittest.main(verbosity=2)
