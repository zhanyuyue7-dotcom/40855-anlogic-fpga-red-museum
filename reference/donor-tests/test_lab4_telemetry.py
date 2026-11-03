import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools" / "lab4_telemetry_server.py"
SPEC = importlib.util.spec_from_file_location("lab4_telemetry_server", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class TelemetryTests(unittest.TestCase):
    def test_parse_valid_packet(self):
        result = MODULE.parse_status_line("@S,1,4,2,1,0,1,1,1,1,0")
        self.assertEqual(
            result,
            {
                "state": 1,
                "found": 4,
                "image": 2,
                "auto": 1,
                "load": 0,
                "display_valid": 1,
                "sd_init": 1,
                "scan_done": 1,
                "disp_buf": 1,
                "write_buf": 0,
            },
        )

    def test_rejects_noise_and_out_of_range_fields(self):
        self.assertIsNone(MODULE.parse_status_line("debug: image=1"))
        self.assertIsNone(MODULE.parse_status_line("@S,1,4,2,2,0,1,1,1,1,0"))

    def test_duplicate_heartbeat_is_filtered(self):
        status = MODULE.parse_status_line("@S,1,4,2,1,0,1,1,1,1,0")
        store = MODULE.StatusStore(event_limit=3)
        self.assertTrue(store.update(status))
        self.assertFalse(store.update(status))
        snapshot = store.snapshot()
        self.assertEqual(snapshot["stats"]["received"], 2)
        self.assertEqual(snapshot["stats"]["duplicates_filtered"], 1)
        self.assertEqual(snapshot["stats"]["changes_kept"], 1)

    def test_event_history_is_bounded(self):
        store = MODULE.StatusStore(event_limit=2)
        for image in range(3):
            status = MODULE.parse_status_line(f"@S,1,4,{image},0,0,1,1,1,0,1")
            self.assertTrue(store.update(status))
        self.assertEqual(len(store.events()), 2)
        self.assertEqual(store.events()[0]["image"], 2)

    def test_serial_reading_can_be_paused_without_clearing_latest_status(self):
        status = MODULE.parse_status_line("@S,1,4,2,1,0,1,1,1,1,0")
        store = MODULE.StatusStore()
        store.set_connection(True, "COM24")
        store.update(status)

        store.set_reading_enabled(False)
        paused = store.snapshot()
        self.assertFalse(paused["reading_enabled"])
        self.assertFalse(paused["connected"])
        self.assertEqual(paused["port"], "COM24")
        self.assertEqual(paused["latest"]["image"], 2)

        store.set_reading_enabled(True)
        self.assertTrue(store.snapshot()["reading_enabled"])


if __name__ == "__main__":
    unittest.main()
