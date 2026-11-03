from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
class Wiring(unittest.TestCase):
 def test_top_and_pin_contract(self):
  top=(ROOT/'work/lab_ex5_i2s/src/user_source/hdl_source/top_tf_hdmi_audio.v').read_text(encoding='utf8')
  pin=(ROOT/'work/lab_ex5_i2s/src/user_source/constraints_source/pin.adc').read_text()
  self.assertNotIn('sw_adjust',top+pin)
  for value in ('.key_down_n(~keypad_keys_pressed[5])','.key_up_n(~keypad_keys_pressed[4])','assign scheduler_key_next = key1_mux_n;','assign scheduler_key_auto = key2_mux_n;'):
   self.assertIn(value,top)
if __name__=='__main__':unittest.main()
