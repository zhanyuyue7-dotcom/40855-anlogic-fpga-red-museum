"""A stale checkpoint must never bypass a fresh hardware build."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('td_build', Path(__file__).resolve().parents[1] / 'tools/td_build.py')
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class CacheTests(unittest.TestCase):
    def test_checkpoint_content_corruption_invalidates_reuse(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            db = root / 'gate.db'
            db.write_bytes(b'correct-netlist')
            record = {'stages': {'gate': {'gate.db': build.sha(db)}}}
            self.assertTrue(build.valid_stage(root, record, 'gate'))
            db.write_bytes(b'changed-netlist')
            self.assertFalse(build.valid_stage(root, record, 'gate'))
            db.unlink()
            self.assertFalse(build.valid_stage(root, record, 'gate'))
            self.assertFalse(build.valid_stage(root, record, 'route'))

    def test_rtl_constraints_rom_tool_and_options_all_invalidate(self):
        original_td = build.TD
        try:
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / 'src').mkdir()
                (root / 'tools').mkdir()
                tracked = ['src/top.v', 'src/timing.sdc', 'src/font.hex', 'src/chip.ipc',
                           'tools/build.tcl', 'tools/td_build.py', 'td.exe']
                for name in tracked:
                    (root / name).write_text('original')
                build.TD = root / 'td.exe'
                base = build.fingerprint(build.inputs(root, 'integrated', False))
                for name in tracked:
                    with self.subTest(name=name):
                        (root / name).write_text('modified')
                        self.assertNotEqual(base, build.fingerprint(build.inputs(root, 'integrated', False)))
                        (root / name).write_text('original')
                self.assertNotEqual(base, build.fingerprint(build.inputs(root, 'integrated', True)))
                (root / 'src/generated.rpt').write_text('irrelevant report')
                self.assertEqual(base, build.fingerprint(build.inputs(root, 'integrated', False)))
        finally:
            build.TD = original_td


if __name__ == '__main__':
    unittest.main()
