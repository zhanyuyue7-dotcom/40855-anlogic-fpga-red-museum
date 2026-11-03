import importlib.util
from pathlib import Path
import struct
import unittest

spec = importlib.util.spec_from_file_location("m3_telemetry", Path(__file__).resolve().parents[1] / "tools/m3_telemetry.py")
telemetry = importlib.util.module_from_spec(spec)
spec.loader.exec_module(telemetry)


def packet(scene=2, flags=2):
    data = bytearray(b"\xa5\x33\x01" + bytes([scene, flags, 2]))
    data.extend(struct.pack("<IIII", 5, 3, 7, 250_000))
    data.append(2)
    checksum = 0
    for value in data:
        checksum ^= value
    data.append(checksum)
    return bytes(data)


class TelemetryTests(unittest.TestCase):
    def test_storage_version_and_mixed_stream(self):
        data = bytearray(packet()[:-1])
        data[2] = 3
        data.extend(bytes([1,4,2,3,0xef,1,0,2,3]))
        data.extend(struct.pack("<IIIIHBBII",306944,307200,4,123456,256,9,3,2,1))
        data.extend(b"\x0f\x0b\x02")
        checksum = 0
        for value in data:
            checksum ^= value
        data.append(checksum)
        self.assertEqual(len(data),64)
        status = telemetry.parse_packet(bytes(data))
        self.assertTrue(status["auto_play"])
        self.assertTrue(status["load_busy"])
        self.assertTrue(status["source_done"])
        self.assertFalse(status["write_done"])
        self.assertEqual(status["source_pixels"],307200)
        self.assertEqual(status["writer_pixels"],306944)
        self.assertEqual(status["auto_key_count"],1)
        self.assertEqual(status["brightness_level"],3)
        self.assertEqual(status["brightness_percent"],100)
        self.assertTrue(status["adjust_mode"])
        self.assertTrue(status["audio_enabled"])
        self.assertTrue(status["storage_fault_active"])
        self.assertEqual(status["storage_fault_code"],3)
        self.assertEqual(status["storage_recovery_count_lsb"],2)
        stream=telemetry.StreamParser()
        statuses=[]
        raw=packet()+bytes(data)+packet()
        for i in range(0,len(raw),5): statuses.extend(stream.feed(raw[i:i+5]))
        self.assertEqual(len(statuses),3)
        self.assertEqual(statuses[1]["write_fifo_words"],256)

    def test_legacy_v2_reserved_bytes_are_not_e3_parameters(self):
        data = bytearray(packet()[:-1])
        data[2] = 2
        data.extend(bytes([1,4,2,3,0xef,1,0,2,3]))
        data.extend(struct.pack("<IIIIHBBII",306944,307200,4,123456,256,9,3,2,1))
        data.extend(b"\x00\x00\x00")
        checksum = 0
        for value in data:
            checksum ^= value
        data.append(checksum)
        status = telemetry.parse_packet(bytes(data))
        self.assertIsNotNone(status)
        self.assertNotIn("brightness_level", status)
        self.assertNotIn("adjust_mode", status)

    def test_fields_and_clock_conversion(self):
        status = telemetry.parse_packet(packet())
        self.assertEqual(status["request_count"], 5)
        self.assertEqual(status["ignored_count"], 3)
        self.assertEqual(status["commit_count"], 7)
        self.assertEqual(status["internal_commit_ms"], 10)
        self.assertTrue(status["latency_valid"])

    def test_partial_noise_and_corrupt_packet_recovery(self):
        stream = telemetry.StreamParser()
        bad = bytearray(packet())
        bad[19] ^= 1
        raw = b"noise@S,1,4\r\n" + bytes(bad) + packet() + packet(1, 1)
        found = []
        for index in range(0, len(raw), 7):
            found.extend(stream.feed(raw[index:index + 7]))
        self.assertEqual([status["scene_id"] for status in found], [2, 1])
        self.assertEqual(stream.invalid, 1)
        self.assertEqual(len(stream.buffer), 0)

    def test_reserved_fields_rejected(self):
        self.assertIsNone(telemetry.parse_packet(packet(3)))
        self.assertIsNone(telemetry.parse_packet(packet(2, 4)))
        self.assertIsNone(telemetry.parse_packet(packet()[:-1]))

    def test_noise_buffer_bounded_and_split_magic(self):
        stream = telemetry.StreamParser()
        for _ in range(100):
            self.assertEqual(stream.feed(b"x" * 4096), [])
            self.assertLessEqual(len(stream.buffer), 1)
        self.assertEqual(stream.feed(packet()[:1]), [])
        self.assertEqual(len(stream.feed(packet()[1:])), 1)


if __name__ == "__main__":
    unittest.main()
