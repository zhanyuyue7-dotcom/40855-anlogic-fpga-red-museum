"""Hardware-compatible telemetry and explicitly separate HXIM image transport."""
from __future__ import annotations

import csv
from contextlib import closing
import hashlib
import io
import ipaddress
import json
import os
from pathlib import Path
import socket
import sqlite3
import struct
import sys
import threading
import time
import uuid
import zlib
from datetime import datetime

from PIL import Image, ImageOps

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from m3_telemetry import StreamParser
from lab4_telemetry_server import parse_status_line


def timestamp():
    return datetime.now().astimezone().isoformat(timespec="milliseconds")


def data_directory():
    path = Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "HX4S20Studio"
    path.mkdir(parents=True, exist_ok=True)
    return path


def endpoint(host, port):
    ipaddress.IPv4Address(host)
    port = int(port)
    if not 1 <= port <= 65535:
        raise ValueError("端口必须在 1–65535 之间")
    return host, port


def command_packet(opcode, sequence):
    if opcode not in range(0x10, 0x16):
        raise ValueError("当前 FPGA 固件不支持该命令")
    payload = bytes((0xA5, 1, sequence & 255, opcode, 0, 0, 0))
    crc = 0
    for byte in payload:
        crc ^= byte
        for _ in range(8):
            crc = ((crc << 1) ^ (7 if crc & 128 else 0)) & 255
    return payload + bytes([crc])


class TelemetryDecoder:
    def __init__(self, mode="自动识别"):
        self.mode = mode
        self.binary = StreamParser()
        self.lines = bytearray()
        self.line_invalid = 0

    @property
    def invalid(self):
        return self.binary.invalid + self.line_invalid

    def feed(self, data):
        if self.mode == "原始 HEX":
            return [{"protocol": "HEX", "raw_hex": data.hex(" ")}]
        result = []
        if self.mode in ("自动识别", "M3 二进制"):
            result.extend({"protocol": "M3", **f} for f in self.binary.feed(data))
        if self.mode in ("自动识别", "Lab4 文本"):
            self.lines.extend(data)
            while b"\n" in self.lines:
                line, _, rest = self.lines.partition(b"\n")
                self.lines = bytearray(rest)
                start = line.rfind(b"@S,")
                if start >= 0:
                    fields = parse_status_line(line[start:].decode("ascii", errors="replace"))
                    if fields is None:
                        self.line_invalid += 1
                    else:
                        result.append({"protocol": "Lab4", **fields,
                                       "bmp_state": fields["state"], "found_count": fields["found"],
                                       "image_index": fields["image"], "auto_play": bool(fields["auto"]),
                                       "load_busy": bool(fields["load"])})
            # Bounded even for a binary stream with no line endings.
            if len(self.lines) > 4096:
                self.lines = self.lines[-256:]
        return result


class SessionStore:
    """Durable full-session storage; UI only retains a small viewing window."""
    def __init__(self, path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with closing(sqlite3.connect(self.path)) as db, db:
            db.execute("PRAGMA journal_mode=WAL")
            db.execute("CREATE TABLE IF NOT EXISTS records (id INTEGER PRIMARY KEY, timestamp TEXT, payload TEXT)")

    def append(self, records):
        with closing(sqlite3.connect(self.path)) as db, db:
            db.executemany("INSERT INTO records(timestamp,payload) VALUES (?,?)",
                           [(r["timestamp"], json.dumps(r, ensure_ascii=False)) for r in records])

    def count(self):
        with closing(sqlite3.connect(self.path)) as db, db:
            return db.execute("SELECT COUNT(*) FROM records").fetchone()[0]

    def export_csv(self, destination):
        destination = Path(destination)
        temp = destination.with_name(destination.name + "." + uuid.uuid4().hex + ".tmp")
        try:
            with closing(sqlite3.connect(self.path)) as db, db:
                db.execute("BEGIN")  # One stable snapshot even during live acquisition.
                fields = {"timestamp", "protocol"}
                for (payload,) in db.execute("SELECT payload FROM records"):
                    fields.update(json.loads(payload))
                names = ["timestamp", "protocol"] + sorted(fields - {"timestamp", "protocol"})
                with temp.open("w", newline="", encoding="utf-8-sig") as stream:
                    writer = csv.DictWriter(stream, fieldnames=names)
                    writer.writeheader()
                    count = 0
                    for (payload,) in db.execute("SELECT payload FROM records ORDER BY id"):
                        row = json.loads(payload)
                        # Avoid Excel formula interpretation of future text protocol fields.
                        row = {k: ("'" + v if isinstance(v, str) and v.startswith(("=", "+", "-", "@")) else v)
                               for k, v in row.items()}
                        writer.writerow(row)
                        count += 1
            os.replace(temp, destination)
            return count
        finally:
            temp.unlink(missing_ok=True)


def prepare_image(path, fit="留边适配"):
    with Image.open(path) as image:
        image = ImageOps.exif_transpose(image).convert("RGB")
        if fit == "居中裁剪":
            image = ImageOps.fit(image, (640, 480), Image.Resampling.LANCZOS)
        elif fit == "拉伸铺满":
            image = image.resize((640, 480), Image.Resampling.LANCZOS)
        else:
            image = ImageOps.pad(image, (640, 480), Image.Resampling.LANCZOS, color=(0, 0, 0))
        output = io.BytesIO()
        image.save(output, format="BMP")
        return output.getvalue()


# HXIM v1 is a NEW receiver protocol. It is NOT implemented in upstream FPGA RTL.
HEADER = struct.Struct("!4sBBIIHI")
HELLO, DATA, FINISH, ACK, ERROR = 1, 2, 3, 128, 129
CHUNK_SIZE = 1024
MAX_IMAGE_SIZE = 2 * 1024 * 1024


def image_packet(kind, transfer, sequence, payload=b""):
    return HEADER.pack(b"HXIM", 1, kind, transfer, sequence, len(payload), zlib.crc32(payload)) + payload


def unpack_image_packet(packet):
    if len(packet) < HEADER.size:
        raise ValueError("short packet")
    magic, version, kind, transfer, sequence, size, crc = HEADER.unpack_from(packet)
    body = packet[HEADER.size:]
    if magic != b"HXIM" or version != 1 or len(body) != size or zlib.crc32(body) != crc:
        raise ValueError("invalid packet")
    return kind, transfer, sequence, body


class TransferCancelled(Exception):
    pass


def upload_image(host, port, data, name, progress=lambda *_: None, cancel=None, timeout=0.35, retries=6):
    target = endpoint(host, port)
    if not data or len(data) > MAX_IMAGE_SIZE:
        raise ValueError("照片大小不合法")
    cancel = cancel or threading.Event()
    transfer = uuid.uuid4().int & 0xFFFFFFFF
    metadata = json.dumps({"name": Path(name).stem + ".bmp", "size": len(data),
                           "sha256": hashlib.sha256(data).hexdigest(), "width": 640, "height": 480}).encode()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.connect(target)

        def exchange(kind, seq, body):
            packet = image_packet(kind, transfer, seq, body)
            for _ in range(retries):
                if cancel.is_set():
                    raise TransferCancelled("已取消照片发送")
                sock.send(packet)
                deadline = time.monotonic() + timeout
                while time.monotonic() < deadline:
                    if cancel.is_set():
                        raise TransferCancelled("已取消照片发送")
                    sock.settimeout(max(0.001, min(0.1, deadline - time.monotonic())))
                    try:
                        reply = unpack_image_packet(sock.recv(2048))
                    except (socket.timeout, ValueError):
                        continue
                    except ConnectionResetError as exc:
                        raise OSError("目标没有照片接收服务；当前 FPGA 固件不支持 HXIM") from exc
                    rk, rt, rs, rb = reply
                    if rt != transfer or rs != seq:
                        continue
                    if rk == ERROR:
                        raise OSError(rb.decode("utf-8", errors="replace"))
                    if rk == ACK and rb[:1] == bytes([kind]):
                        return
            raise TimeoutError(f"照片接收端未确认第 {seq} 包；请检查接收服务、IP、端口和防火墙")

        exchange(HELLO, 0, metadata)
        progress(0, len(data))
        count = 0
        for offset in range(0, len(data), CHUNK_SIZE):
            count += 1
            chunk = data[offset:offset + CHUNK_SIZE]
            exchange(DATA, count, chunk)
            progress(min(offset + len(chunk), len(data)), len(data))
        exchange(FINISH, count + 1, b"")
    return hashlib.sha256(data).hexdigest()


class ImageReceiver:
    """Bounded reference receiver with duplicate ACK handling and SHA-256 finalization."""
    def __init__(self, output):
        self.output = Path(output)
        self.output.mkdir(parents=True, exist_ok=True)
        self.active = {}
        self.completed = {}

    def handle(self, packet, peer):
        try:
            kind, transfer, sequence, body = unpack_image_packet(packet)
        except ValueError:
            return None
        now = time.monotonic()
        self.active = {k: v for k, v in self.active.items() if now - v["time"] < 30}
        self.completed = {k: v for k, v in self.completed.items() if now - v[0] < 30}
        key = (peer, transfer)
        try:
            if kind == HELLO:
                metadata = json.loads(body)
                size = metadata["size"]
                digest = metadata["sha256"]
                if type(size) is not int or not 0 < size <= MAX_IMAGE_SIZE or len(digest) != 64:
                    raise ValueError("invalid image metadata")
                if key not in self.active:
                    if len(self.active) >= 8:
                        raise ValueError("receiver busy")
                    self.active[key] = {"metadata": metadata, "data": bytearray(), "next": 1, "time": now}
                elif self.active[key]["metadata"] != metadata:
                    raise ValueError("transfer metadata changed")
            elif kind == FINISH and key in self.completed:
                if sequence != self.completed[key][1]:
                    raise ValueError("unexpected final sequence")
            elif kind in (DATA, FINISH):
                state = self.active.get(key)
                if state is None:
                    raise ValueError("unknown or expired transfer")
                state["time"] = now
                if kind == DATA:
                    if not 1 <= len(body) <= CHUNK_SIZE or sequence > state["next"] or sequence < 1:
                        raise ValueError("invalid data sequence")
                    if sequence == state["next"]:
                        if len(state["data"]) + len(body) > state["metadata"]["size"]:
                            raise ValueError("image exceeds declared size")
                        state["data"].extend(body)
                        state["next"] += 1
                else:
                    data = state["data"]
                    meta = state["metadata"]
                    if sequence != state["next"] or len(data) != meta["size"] or hashlib.sha256(data).hexdigest() != meta["sha256"]:
                        raise ValueError("incomplete image or SHA-256 mismatch")
                    with Image.open(io.BytesIO(data)) as im:
                        if im.format != "BMP" or im.size != (640, 480) or im.mode != "RGB":
                            raise ValueError("expected 640x480 RGB BMP")
                        im.verify()
                    # Never use an untrusted remote filename as a filesystem path.
                    path = self.output / f"image_{transfer:08x}_{uuid.uuid4().hex[:8]}.bmp"
                    temp = path.with_suffix(".part")
                    try:
                        temp.write_bytes(data)
                        os.replace(temp, path)
                    finally:
                        temp.unlink(missing_ok=True)
                    self.completed[key] = (now, sequence, str(path))
                    del self.active[key]
            else:
                return None
            return image_packet(ACK, transfer, sequence, bytes([kind]))
        except (ValueError, KeyError, TypeError, OSError) as exc:
            return image_packet(ERROR, transfer, sequence, str(exc).encode("utf-8")[:512])

    def serve(self, host, port, stop=None, ready=None):
        stop = stop or threading.Event()
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.bind((host, port))
            sock.settimeout(0.2)
            if ready:
                ready(sock.getsockname())
            while not stop.is_set():
                try:
                    data, peer = sock.recvfrom(4096)
                except (socket.timeout, ConnectionResetError):
                    continue
                reply = self.handle(data, peer)
                if reply:
                    sock.sendto(reply, peer)
