"""Keep regenerated PLL sources and the refresh time base consistent."""
from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET

SRC = Path(__file__).resolve().parents[1] / "work/lab_ex5_i2s/src/user_source/hdl_source"


class SdramClockConfigTests(unittest.TestCase):
    def test_verilog_vhdl_ipc_and_refresh_timebase_agree(self):
        verilog = (SRC / "IP/sys_pll.v").read_text(encoding="utf-8")
        vhdl = (SRC / "IP/sys_pll.vhd").read_text(encoding="utf-8")
        ipc = ET.parse(SRC / "IP/sys_pll.ipc")
        clocks = ipc.findall("./Page3/clocks/clock")
        values = {}
        for clock in clocks:
            index = int(clock.findtext("id"))
            divisor = int(clock.findtext("clock_division_factor"))
            frequency = float(clock.findtext("clock_frequency").removesuffix("MHz"))
            phase = float(clock.findtext("phase_shift").removesuffix("deg"))
            for name in (f"CLKC{index}_DIV", f"CLKC{index}_CPHASE", f"CLKC{index}_FPHASE"):
                v = int(re.search(rf"\.{name}\((\d+)\)", verilog).group(1))
                h = int(re.search(rf"{name}\s*=>\s*(\d+)", vhdl).group(1))
                self.assertEqual(v, h, name)
                values[name] = v
            self.assertEqual(values[f"CLKC{index}_DIV"], divisor)
            self.assertEqual(frequency * divisor, 1000.0, "1 GHz VCO must stay unchanged")
            actual_phase = ((values[f"CLKC{index}_CPHASE"] + 1) % divisor) * 360.0 / divisor
            self.assertEqual(values[f"CLKC{index}_FPHASE"], 0)
            self.assertAlmostEqual(actual_phase, phase)
        self.assertEqual(values["CLKC0_DIV"], 10, "SD/SPI clock must remain 100 MHz")
        self.assertEqual(values["CLKC1_DIV"], values["CLKC2_DIV"])
        header = (SRC / "include/global_def.v").read_text(encoding="utf-8")
        refresh_hz = int(re.search(r"`define\s+SDR_CLK_HZ\s+(\d+)", header).group(1))
        self.assertEqual(refresh_hz, 1000000000 // values["CLKC1_DIV"])


if __name__ == "__main__":
    unittest.main()
