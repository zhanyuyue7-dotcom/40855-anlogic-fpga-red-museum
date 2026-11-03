import csv
import gzip
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from report_view import DATA, ReportDialog, export_trace, load_manifest, trace_source


class ReportTests(unittest.TestCase):
    def test_archive_hash_and_statistics(self):
        m = load_manifest()
        self.assertEqual(len(m["cases"]), 42)
        for name, expected in m["sources"].items():
            self.assertEqual(hashlib.sha256((DATA / "sources" / name).read_bytes()).hexdigest(), expected)
        trace = m["traces"][1]
        h = hashlib.sha256()
        count = 0
        with gzip.open(DATA / trace["source"], "rb") as stream:
            for line in stream:
                h.update(line)
                count += json.loads(line).get("kind") == "status"
        self.assertEqual(count, 143680)
        self.assertEqual(h.hexdigest(), trace["raw_sha256"])
        self.assertEqual(sum(b["changes"] for b in trace["minute_bins"]), 2892)
        self.assertEqual(m["latency"]["n"], 4)
        self.assertAlmostEqual(m["latency"]["mean_ms"], 12.25702)

    def test_full_csv_preserves_source_times_and_all_rows(self):
        m = load_manifest()
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "history.csv"
            self.assertEqual(export_trace(m, 1, path), 143680)
            with path.open(encoding="utf-8-sig", newline="") as stream:
                reader = csv.DictReader(stream)
                first = next(reader)
                count = 1
                last = first
                for last in reader:
                    count += 1
            self.assertEqual(count, 143680)
            self.assertEqual(first["timestamp"], m["traces"][1]["first"])
            self.assertEqual(last["timestamp"], m["traces"][1]["last"])
            self.assertEqual(first["evidence_type"], "历史实测记录")
            self.assertEqual(first["source_sha256"], m["traces"][1]["source_sha256"])

    def test_current_72h_archive_matches_independent_audit(self):
        m = load_manifest()
        trace = m["traces"][0]
        source = trace_source(trace)
        audit = json.loads((source.parent / "audit.json").read_text(encoding="utf-8"))
        with source.open("rb") as stream:
            self.assertEqual(hashlib.file_digest(stream, "sha256").hexdigest(), trace["source_sha256"])
        self.assertEqual(trace["records"], audit["kinds"]["status"])
        self.assertEqual(trace["span_seconds"], audit["status_span_seconds"])
        self.assertEqual(sum(b["changes"] for b in trace["minute_bins"]), audit["statistics"]["image_index_changes"])
        self.assertEqual(sum(b["records"] for b in trace["minute_bins"]), trace["records"])
        self.assertEqual(trace["samples"][0]["timestamp"], audit["first_status_timestamp"])
        self.assertEqual(trace["samples"][-1]["timestamp"], audit["last_status_timestamp"])
        self.assertEqual(trace["samples"][-1]["record_number"], 5184000)
        self.assertEqual(trace["test_summary"]["test_type"], "hardware_stability_test")

    def test_72h_export_resolves_bundled_source_and_preserves_rows(self):
        trace = dict(load_manifest()["traces"][0])
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            data = root / "report_data"
            data.mkdir()
            bundled = root / "long_run_data"
            bundled.mkdir()
            rows = [{"kind": "boot", "timestamp": "2026-10-28T16:39:57+08:00"}] + trace["samples"][:2]
            source = bundled / "parsed.jsonl.gz"
            with gzip.open(source, "wt", encoding="utf-8") as stream:
                for row in rows:
                    stream.write(json.dumps(row) + "\n")
            trace["source_sha256"] = hashlib.sha256(source.read_bytes()).hexdigest()
            target = root / "out.csv"
            with patch("report_view.DATA", data):
                self.assertEqual(trace_source(trace), source)
                self.assertEqual(export_trace({"traces": [trace]}, 0, target), 2)
                with target.open(encoding="utf-8-sig", newline="") as stream:
                    result = list(csv.DictReader(stream))
                self.assertEqual([r["timestamp"] for r in result], [r["timestamp"] for r in rows[1:]])
                trace["source_sha256"] = "bad hash"
                with self.assertRaises(ValueError):
                    export_trace({"traces": [trace]}, 0, target)

    def test_report_ui_never_connects_hardware_and_replay_works(self):
        from PyQt5.QtWidgets import QApplication
        app = QApplication.instance() or QApplication([])
        with patch("serial.serial_for_url", side_effect=AssertionError("must not open UART")), patch("socket.socket", side_effect=AssertionError("must not connect network")):
            dialog = ReportDialog()
            self.assertIn("72小时", dialog.trace_choice.currentText())
            self.assertIn("5,184,000", dialog.history_info.text())
            self.assertEqual(dialog.cases_table.rowCount(), 42)
            self.assertEqual(dialog.event_table.rowCount(), 4)
            dialog.play()
            dialog.advance()
            self.assertEqual(dialog.slider.value(), 1)
            dialog.pause()
            self.assertFalse(dialog.play_timer.isActive())
            dialog.trace_choice.setCurrentIndex(2)
            self.assertIn("605", dialog.history_info.text())
            dialog.filter.setCurrentText("待验证")
            self.assertFalse(dialog.cases_table.isRowHidden(18))
            self.assertTrue(dialog.cases_table.isRowHidden(0))
            dialog.close()
            app.processEvents()

    def test_long_run_plans_are_budgets_not_test_results(self):
        from report_extensions import long_run_budget
        plans = load_manifest()["extensions"]["plans"]
        self.assertEqual([p["target_hours"] for p in plans], [8, 24, 72])
        for p in plans:
            self.assertEqual(p["planned_frames"], p["target_hours"] * 3600 * 20)
            self.assertEqual(p["raw_bytes"], p["planned_frames"] * 64)
            self.assertIsNone(p["measured_elapsed_seconds"])
            self.assertIsNone(p["measured_faults"])
            self.assertIsNone(p["passed"])
        self.assertEqual(plans[-1]["planned_frames"], 5184000)
        with self.assertRaises(ValueError):
            long_run_budget(-1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
