import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from analyze_m5_uart import summarize  # noqa: E402


class M5MetricsTests(unittest.TestCase):
    def test_counter_gaps_are_reported_and_not_filled(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.jsonl"
            rows = [
                {"kind": "status", "request_count": 0, "latency_valid": False},
                {"kind": "status", "request_count": 1, "latency_valid": True, "internal_commit_ms": 4.0},
                {"kind": "status", "request_count": 3, "latency_valid": True, "internal_commit_ms": 7.0},
            ]
            path.write_text("\n".join(json.dumps(row) for row in rows), encoding="utf-8")
            result = summarize(path, "test")
            self.assertEqual(result["event_samples"], 1)
            self.assertEqual(result["counter_gap_events"], 1)
            self.assertEqual(result["latency_ms"]["maximum"], 4.0)


if __name__ == "__main__":
    unittest.main()
