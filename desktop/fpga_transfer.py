"""HXFP v1 host transport. Paired synthesizable receiver: fpga_upload/rtl/hxfp_receiver.v.

This protocol requires integration in the target bitstream; legacy 8-byte control
firmware does not implement it. No successful upload is inferred from sendto().
"""
from __future__ import annotations
from dataclasses import dataclass, asdict
import io
import json
import math
from pathlib import Path
import socket
import struct
import threading
import time
import uuid
import zlib

from PIL import Image
from core import endpoint, TransferCancelled, timestamp, data_directory

WIDTH, HEIGHT, FORMAT_RGB565_LE = 640, 480, 1
IMAGE_BYTES = WIDTH * HEIGHT * 2
MAX_CHUNK = 1024
PROBE, BEGIN, DATA, COMMIT, ABORT = 1, 2, 3, 4, 5
OK, BAD_META, BUSY, BAD_SEQUENCE, BAD_CRC, BAD_SESSION, STORAGE_ERROR, INCOMPLETE, UNSUPPORTED = range(9)
IDLE, RECEIVING, DISPLAYED = 0, 1, 2
HEADER = struct.Struct("!4sBBIIH")
META = struct.Struct("!HHII")
RESPONSE = struct.Struct("!BBHIII")
ERRORS = {1: "图片尺寸或长度不匹配", 2: "设备正忙，已有其他上传", 3: "包序号不匹配",
          4: "整帧CRC32校验失败", 5: "上传会话不存在或已失效", 6: "设备存储/显示接口异常",
          7: "设备尚未收到完整图片", 8: "设备不支持此操作"}


def packet(opcode, session, sequence, payload=b""):
    if len(payload) > MAX_CHUNK:
        raise ValueError("HXFP payload too large")
    head = HEADER.pack(b"HXFP", 1, opcode, session, sequence, len(payload))
    return head + struct.pack("!I", zlib.crc32(head + payload)) + payload


def unpack(data):
    if len(data) < 20:
        raise ValueError("short HXFP packet")
    magic, version, op, session, seq, length = HEADER.unpack_from(data)
    if magic != b"HXFP" or version != 1 or length > MAX_CHUNK or len(data) != length + 20:
        raise ValueError("invalid HXFP header")
    body = data[20:]
    if zlib.crc32(data[:16] + body) != struct.unpack_from("!I", data, 16)[0]:
        raise ValueError("HXFP CRC32 mismatch")
    return op, session, seq, body


def encode_rgb565(bmp):
    """Top-left row first; RRRRRGGG GGGBBBBB as little endian uint16 pixels."""
    with Image.open(io.BytesIO(bmp)) as image:
        if image.size != (WIDTH, HEIGHT):
            raise ValueError("设备图片必须为640×480")
        rgb = image.convert("RGB").tobytes()
    output = bytearray(IMAGE_BYTES)
    for src in range(0, len(rgb), 3):
        r, g, b = rgb[src:src + 3]
        word = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
        at = (src // 3) * 2
        output[at] = word & 255
        output[at + 1] = word >> 8
    return bytes(output)


@dataclass(frozen=True)
class DeviceStatus:
    status: int
    phase: int
    max_chunk: int
    received_bytes: int
    image_crc32: int
    dimensions: int

    @property
    def width(self):
        return self.dimensions >> 16

    @property
    def height(self):
        return self.dimensions & 65535


class DeviceError(OSError):
    pass


class DeviceClient:
    def __init__(self, host, port=5002, timeout=0.7, retries=6, cancel=None, event=lambda *_: None):
        self.target = endpoint(host, port)
        if not math.isfinite(timeout) or timeout <= 0 or not isinstance(retries, int) or retries < 1:
            raise ValueError("确认超时必须为正数，发送次数必须为正整数")
        self.timeout, self.retries = timeout, retries
        self.cancel = cancel or threading.Event()
        self.event = event
        self.session = (uuid.uuid4().int & 0xFFFFFFFF) or 1
        self.sock = None
        self.retransmissions = 0

    def __enter__(self):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.connect(self.target)  # filter incoming packets to the selected device
        return self

    def __exit__(self, *_):
        self.sock.close()

    def exchange(self, op, sequence, payload=b"", allow_cancel=True, retries=None, timeout=None):
        wait_seconds = self.timeout if timeout is None else timeout
        data = packet(op, self.session, sequence, payload)
        for attempt in range(self.retries if retries is None else retries):
            if allow_cancel and self.cancel.is_set():
                raise TransferCancelled("用户取消图片传输")
            if attempt:
                self.retransmissions += 1
                self.event("retry", {"opcode": op, "sequence": sequence, "attempt": attempt + 1})
            self.sock.send(data)
            deadline = time.monotonic() + wait_seconds
            while time.monotonic() < deadline:
                if allow_cancel and self.cancel.is_set():
                    raise TransferCancelled("用户取消图片传输")
                self.sock.settimeout(max(0.001, min(0.1, deadline - time.monotonic())))
                try:
                    received = self.sock.recv(2048)
                except socket.timeout:
                    continue
                except ConnectionResetError as exc:
                    raise DeviceError("设备图片端口未开放；请确认固件已接入HXFP，默认UDP 5002") from exc
                try:
                    kind, session, seq, body = unpack(received)
                    if kind != op | 0x80 or session != self.session or seq != sequence or len(body) != RESPONSE.size:
                        continue
                    reply = DeviceStatus(*RESPONSE.unpack(body))
                except (ValueError, struct.error):
                    continue
                if reply.status != OK:
                    raise DeviceError(ERRORS.get(reply.status, f"设备错误 {reply.status}"))
                return reply
        if op == PROBE:
            raise TimeoutError("设备未回应图片能力查询。网口控制可用不代表支持图片上传；需先接入配套HXFP接收模块。")
        raise TimeoutError(f"设备未确认包 {sequence}（操作{op}）；停止传输，未判定显示成功")

    def probe(self):
        reply = self.exchange(PROBE, 0)
        if (reply.width, reply.height) != (WIDTH, HEIGHT) or not 2 <= reply.max_chunk <= MAX_CHUNK or reply.max_chunk % 2:
            raise DeviceError("设备图片能力与640×480 RGB565协议不匹配")
        return reply


def probe_device(host, port=5002, cancel=None):
    with DeviceClient(host, port, cancel=cancel) as client:
        return client.probe()


def upload_to_fpga(host, port, bmp, name, progress=lambda *_: None, cancel=None,
                   stage=lambda *_: None, receipt_dir=None, timeout=0.7, retries=6,
                   commit_timeout=3.0):
    if not math.isfinite(commit_timeout) or commit_timeout <= 0:
        raise ValueError("显示提交确认超时必须为正数")
    cancel = cancel or threading.Event()
    started = time.monotonic()
    receipt = {"protocol": "HXFP/1", "target": f"{host}:{port}", "source_name": Path(name).name,
               "started_at": timestamp(), "status": "starting", "display_confirmed": False,
               "bytes_confirmed": 0, "retransmissions": 0, "events": [],
               "ack_timeout_seconds": timeout, "commit_timeout_seconds": commit_timeout,
               "max_attempts": retries, "commit_requested": False}
    receipt_dir = Path(receipt_dir) if receipt_dir else data_directory() / "transfers"
    receipt_dir.mkdir(parents=True, exist_ok=True)
    receipt_path = receipt_dir / (uuid.uuid4().hex + ".json")
    def event(kind, detail):
        if len(receipt["events"]) < 2000:
            receipt["events"].append({"kind": kind, "elapsed_s": round(time.monotonic() - started, 3), **detail})
    try:
        stage("正在转换为640×480 RGB565像素…")
        pixels = encode_rgb565(bmp)
        crc = zlib.crc32(pixels)
        receipt.update({"width": WIDTH, "height": HEIGHT, "format": "RGB565_LE_TOP_DOWN",
                        "bytes_total": len(pixels), "image_crc32": f"{crc:08x}"})
        with DeviceClient(host, port, timeout=timeout, retries=retries, cancel=cancel, event=event) as client:
            receipt["session"] = client.session
            begun = False
            committing = False
            try:
                stage("正在查询FPGA图片接收能力…")
                capabilities = client.probe()
                receipt["capabilities"] = asdict(capabilities)
                stage("正在申请设备空闲帧缓存…")
                # Even a lost BEGIN ACK can leave a live device session; cancel it on failure.
                begun = True
                response = client.exchange(BEGIN, 0, META.pack(WIDTH, HEIGHT, len(pixels), crc))
                if response.phase != RECEIVING or response.received_bytes != 0 or response.image_crc32 != 0:
                    raise DeviceError("设备未进入空帧接收状态")
                running_crc = 0
                sequence = 0
                for offset in range(0, len(pixels), capabilities.max_chunk):
                    sequence += 1
                    chunk = pixels[offset:offset + capabilities.max_chunk]
                    response = client.exchange(DATA, sequence, chunk)
                    end = offset + len(chunk)
                    running_crc = zlib.crc32(chunk, running_crc)
                    if response.phase != RECEIVING or response.received_bytes != end or response.image_crc32 != running_crc:
                        raise DeviceError("设备确认的写入长度/CRC与本机不一致")
                    receipt["bytes_confirmed"] = end
                    progress(end, len(pixels))
                if cancel.is_set():
                    raise TransferCancelled("用户取消图片传输")
                stage("全部像素已接收；正在等待设备帧边界显示提交…")
                committing = True
                receipt["commit_requested"] = True
                receipt["pixels_confirmed_elapsed_s"] = round(time.monotonic() - started, 3)
                # Once commit is sent, resolve it rather than report cancellation as rollback.
                response = client.exchange(COMMIT, sequence + 1, allow_cancel=False, timeout=commit_timeout)
                if response.phase != DISPLAYED or response.received_bytes != len(pixels) or response.image_crc32 != crc:
                    raise DeviceError("设备尚未确认完整图片的显示提交")
                receipt.update(status="display_confirmed", display_confirmed=True)
                stage("设备已确认帧边界提交")
            except Exception:
                if begun and not committing:
                    try:
                        response = client.exchange(ABORT, 0xFFFFFFFF, allow_cancel=False, retries=2)
                        receipt["abort_confirmed"] = response.phase == IDLE
                    except Exception as abort_error:
                        receipt["abort_confirmed"] = False
                        receipt["abort_error"] = str(abort_error)
                if committing:
                    receipt["status"] = "commit_result_unknown"
                raise
            finally:
                receipt["retransmissions"] = client.retransmissions
        return receipt
    except Exception as exc:
        if receipt["status"] != "commit_result_unknown":
            receipt["status"] = "cancelled" if isinstance(exc, TransferCancelled) else "failed"
        receipt["error"] = str(exc)
        raise
    finally:
        receipt["elapsed_seconds"] = round(time.monotonic() - started, 3)
        receipt["receipt_path"] = str(receipt_path)
        receipt_path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2), encoding="utf-8")
