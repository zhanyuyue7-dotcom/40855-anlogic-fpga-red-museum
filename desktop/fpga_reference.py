"""Software reference endpoint for HXFP integration tests; NOT a hardware driver."""
import struct
import zlib
from fpga_transfer import (unpack, packet, RESPONSE, META, PROBE, BEGIN, DATA, COMMIT, ABORT,
                           WIDTH, HEIGHT, IMAGE_BYTES, MAX_CHUNK, DeviceStatus)


class ReferenceDevice:
    def __init__(self):
        self.owner = None
        self.active = False
        self.completed = False
        self.data = bytearray()
        self.expected_crc = 0
        self.next_seq = 1
        self.previous = None
        self.completed_seq = None
        self.displayed = 0
        self.writes = []
        self.commit_ready = True

    def expire(self):
        self.active = self.completed = False
        self.data.clear()

    def handle(self, raw, peer):
        try:
            op, session, seq, body = unpack(raw)
        except ValueError:
            return None
        if session == 0:
            return None
        owner = (peer, session)
        phase = 1 if self.active else (2 if self.completed else 0)
        def reply(status=0, ph=None, count=None, crc=None):
            payload = RESPONSE.pack(status, phase if ph is None else ph, MAX_CHUNK,
                                    len(self.data) if count is None else count,
                                    zlib.crc32(self.data) if crc is None else crc,
                                    (WIDTH << 16) | HEIGHT)
            return packet(op | 0x80, session, seq, payload)
        def error(status, ph=0):
            return reply(status, ph, 0, 0)
        if op == PROBE:
            return error(1) if body else reply()
        if op == BEGIN:
            if len(body) != 12 or seq != 0:
                return error(1)
            width, height, length, crc = META.unpack(body)
            if (width, height, length) != (WIDTH, HEIGHT, IMAGE_BYTES):
                return error(1)
            if self.active:
                return reply(0 if owner == self.owner and crc == self.expected_crc else 2, 1)
            if self.completed and owner == self.owner:
                return reply(3, 2)
            self.owner = owner
            self.active, self.completed = True, False
            self.data.clear()
            self.expected_crc = crc
            self.next_seq = 1
            self.previous = None
            return reply(0, 1, 0, 0)
        if op == DATA:
            if not self.active or owner != self.owner:
                return error(5)
            if seq == self.next_seq - 1 and self.previous == raw:
                return reply(0, 1)
            if seq != self.next_seq:
                return reply(3, 1)
            if not body or len(body) % 2 or len(self.data) + len(body) > IMAGE_BYTES:
                return reply(1, 1)
            offset = len(self.data)
            for i in range(0, len(body), 2):
                self.writes.append(((offset + i) // 2, int.from_bytes(body[i:i+2], "little")))
            self.data.extend(body)
            self.next_seq += 1
            self.previous = raw
            return reply(0, 1)
        if op == COMMIT:
            if body:
                return error(1)
            if self.completed and owner == self.owner and seq == self.completed_seq:
                return reply(0, 2)
            if not self.active or owner != self.owner:
                return error(5)
            if seq != self.next_seq:
                return reply(3, 1)
            if len(self.data) != IMAGE_BYTES:
                return reply(7, 1)
            if zlib.crc32(self.data) != self.expected_crc:
                return reply(4, 1)
            if not self.commit_ready:
                return None
            self.active, self.completed = False, True
            self.completed_seq = seq
            self.displayed += 1
            return reply(0, 2)
        if op == ABORT:
            if body:
                return error(1)
            if owner != self.owner or not (self.active or self.completed):
                return error(5)
            if self.active:
                self.active = self.completed = False
                self.data.clear()
                return reply(0, 0, 0, 0)
            return reply(0, 2)
        return error(8)
