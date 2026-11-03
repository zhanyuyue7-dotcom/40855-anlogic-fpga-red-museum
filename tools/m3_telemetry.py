"""Read-only M3 UART capture. This program never sends control to the FPGA."""
from __future__ import annotations

import argparse
from datetime import datetime
import json
from pathlib import Path
import struct
import time

MAGIC = b"\xa5\x33"
PACKET_SIZE = 24
PACKET_SIZES = {1: 24, 2: 64, 3: 64}
PIXEL_CLOCK_HZ = 25_000_000


def parse_packet(packet: bytes) -> dict[str, int | bool | float] | None:
    if len(packet) < 3 or packet[:2] != MAGIC or len(packet) != PACKET_SIZES.get(packet[2]):
        return None
    checksum = 0
    for byte in packet:
        checksum ^= byte
    if checksum or packet[3] > 2 or packet[5] > 2 or packet[22] > 2 or packet[4] & ~3:
        return None
    requests, ignored, commits, cycles = struct.unpack_from("<IIII", packet, 6)
    fields = {
        "scene_id": packet[3],
        "request_pending": bool(packet[4] & 1),
        "latency_valid": bool(packet[4] & 2),
        "requested_scene_id": packet[5],
        "request_count": requests,
        "ignored_count": ignored,
        "commit_count": commits,
        "latency_cycles": cycles,
        "internal_commit_ms": cycles * 1000 / PIXEL_CLOCK_HZ,
        "last_event_scene": packet[22],
    }
    if packet[2] in (2, 3):
        flags = packet[27]
        fields.update({
            "bmp_state": packet[23], "found_count": packet[24],
            "image_index": packet[25], "load_index": packet[26],
            "auto_play": bool(flags & 1), "load_busy": bool(flags & 2),
            "bmp_ready": bool(flags & 4), "source_done": bool(flags & 8),
            "write_done": bool(flags & 16), "sd_init": bool(flags & 32),
            "scan_done": bool(flags & 64), "next_pending": bool(flags & 128),
            "display_buffer": packet[28], "write_buffer": packet[29],
            "writer_state": packet[30], "reader_state": packet[31],
            "writer_pixels": struct.unpack_from("<I", packet, 32)[0],
            "source_pixels": struct.unpack_from("<I", packet, 36)[0],
            "write_finish_count": struct.unpack_from("<I", packet, 40)[0],
            "auto_counter": struct.unpack_from("<I", packet, 44)[0],
            "write_fifo_words": struct.unpack_from("<H", packet, 48)[0],
            "memory_flags": packet[50], "sd_flags": packet[51],
            "next_key_count": struct.unpack_from("<I", packet, 52)[0],
            "auto_key_count": struct.unpack_from("<I", packet, 56)[0],
        })
        if packet[2] == 2:
            if packet[60] or packet[61] or packet[62]:
                return None
        else:
            parameter = packet[60]
            fault = packet[61]
            if parameter & ~0x0F or fault & ~0x0F or (fault & 0x07) > 6:
                return None
            brightness_level = parameter & 0x03
            fields.update({
                "brightness_level": brightness_level,
                "brightness_percent": (brightness_level + 1) * 25,
                "adjust_mode": bool(parameter & 0x04),
                "audio_enabled": bool(parameter & 0x08),
                "storage_fault_code": fault & 0x07,
                "storage_fault_active": bool(fault & 0x08),
                "storage_recovery_count_lsb": packet[62],
            })
    return fields


class StreamParser:
    def __init__(self) -> None:
        self.buffer = bytearray()
        self.invalid = 0

    def feed(self, data: bytes) -> list[dict[str, int | bool | float]]:
        self.buffer.extend(data)
        result = []
        while True:
            start = self.buffer.find(MAGIC)
            if start < 0:
                self.buffer[:] = self.buffer[-1:] if self.buffer.endswith(MAGIC[:1]) else b""
                break
            if start:
                del self.buffer[:start]
            if len(self.buffer) < 3:
                break
            size = PACKET_SIZES.get(self.buffer[2])
            if size is None:
                self.invalid += 1
                del self.buffer[0]
                continue
            if len(self.buffer) < size:
                break
            fields = parse_packet(bytes(self.buffer[:size]))
            if fields is None:
                self.invalid += 1
                del self.buffer[0]
            else:
                result.append(fields)
                del self.buffer[:size]
        return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", help="Current CH340 port; never assume COM39 is permanent")
    parser.add_argument("--seconds", type=float, default=180)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--list-ports", action="store_true")
    parser.add_argument("--quiet", action="store_true", help="Keep all changed snapshots in JSONL without printing each one")
    args = parser.parse_args()
    if args.seconds <= 0:
        parser.error("--seconds must be positive")
    import serial
    from serial.tools import list_ports
    ports = list(list_ports.comports())
    if args.list_ports:
        for port in ports:
            print(f"{port.device}: {port.description}, {port.hwid}")
        return
    if not args.port:
        candidates = [port.device for port in ports if port.vid == 0x1A86 and port.pid == 0x7523]
        if len(candidates) != 1:
            parser.error("Expected one CH340; use --list-ports and specify --port")
        args.port = candidates[0]
    output = args.output or Path(__file__).resolve().parents[1] / "diagnostics" / (
        "m3-uart-" + datetime.now().strftime("%Y%m%d-%H%M%S") + ".jsonl"
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    stream = StreamParser()
    received = duplicates = changes = 0
    previous = None
    started = time.monotonic()
    print(f"Read-only capture {args.port}, 115200 8N1 -> {output}")
    print("Latency is debounced event -> internal scene_commit. It excludes button debounce and display latency.")
    # Exclusive creation preserves prior captures and serial opening sends no data.
    with output.open("x", encoding="utf-8") as logfile:
        with serial.Serial(args.port, 115200, timeout=0.2) as device:
            try:
                while time.monotonic() - started < args.seconds:
                    for fields in stream.feed(device.read(4096)):
                        received += 1
                        if fields == previous:
                            duplicates += 1
                            continue
                        changes += 1
                        previous = fields
                        record = {"kind": "status", "timestamp": datetime.now().astimezone().isoformat(), **fields}
                        encoded = json.dumps(record, ensure_ascii=False)
                        logfile.write(encoded + "\n")
                        logfile.flush()
                        if not args.quiet:
                            print(encoded)
            except KeyboardInterrupt:
                pass
        summary = {"kind": "summary", "port": args.port, "received": received,
                   "changes": changes, "duplicate_heartbeats": duplicates, "invalid": stream.invalid}
        logfile.write(json.dumps(summary) + "\n")
        print(json.dumps(summary))
    if not received:
        raise SystemExit("No valid M3 packets; check UART cable and loaded bitstream. lab4 @S packets are a different protocol.")


if __name__ == "__main__":
    main()
