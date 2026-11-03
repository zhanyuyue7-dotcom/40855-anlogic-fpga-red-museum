import re
import unittest
from pathlib import Path

TOP = Path(__file__).resolve().parents[1] / "work/lab_ex5_i2s/src/user_source/hdl_source/top_tf_hdmi_audio.v"


class ResetPolicyTests(unittest.TestCase):
    def test_video_timing_is_not_reset_by_storage_recovery(self):
        source = TOP.read_text(encoding="utf-8")
        match = re.search(
            r"video_timing_data\s+video_timing_data_m0\((.*?)\n\);",
            source,
            re.S,
        )
        self.assertIsNotNone(match, "video timing instance not found")
        instance = match.group(1)
        self.assertRegex(instance, r"\.rst\s*\(rst_all\)")
        self.assertNotRegex(instance, r"\.rst\s*\(storage_reset_mem\)")

    def test_frame_path_keeps_local_storage_reset(self):
        source = TOP.read_text(encoding="utf-8")
        match = re.search(
            r"frame_read_write\s+#\(.*?\)\s*frame_read_write_m0\((.*?)\n\);",
            source,
            re.S,
        )
        self.assertIsNotNone(match, "frame read/write instance not found")
        self.assertRegex(match.group(1), r"\.rst\s*\(storage_reset_mem\)")


if __name__ == "__main__":
    unittest.main()
