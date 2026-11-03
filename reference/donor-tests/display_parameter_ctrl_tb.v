`timescale 1ns/1ps
module display_parameter_ctrl_tb;
 reg clk=0,rst=1,sw_audio_enable=0,key_down_n=1,key_up_n=1;
 wire adjust_mode,audio_enable;
 wire [1:0] brightness_level;
 display_parameter_ctrl #(.DEBOUNCE_CYCLES(3)) dut(
   .clk(clk),.rst(rst),.sw_audio_enable(sw_audio_enable),
   .key_down_n(key_down_n),.key_up_n(key_up_n),
   .adjust_mode(adjust_mode),.brightness_level(brightness_level),.audio_enable(audio_enable));
 always #5 clk=~clk;
 task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 task settle;integer i;begin for(i=0;i<10;i=i+1)tick;end endtask
 task down;begin key_down_n=0;settle;key_down_n=1;settle;end endtask
 task up;begin key_up_n=0;settle;key_up_n=1;settle;end endtask
 always @(negedge clk) if(!rst && adjust_mode!==0)$fatal(1,"Adjustment mode must never activate");
 initial begin
  repeat(3)tick;rst=0;settle;
  if(brightness_level!==3 || audio_enable!==0)$fatal(1,"reset defaults");
  key_down_n=0;tick;key_down_n=1;settle;
  if(brightness_level!==3)$fatal(1,"bounce changed brightness");
  down;if(brightness_level!==2)$fatal(1,"mode-free S6 step");
  key_down_n=0;settle;repeat(8)settle;
  if(brightness_level!==1)$fatal(1,"held key repeated");
  key_down_n=1;settle;
  repeat(5)down;if(brightness_level!==0)$fatal(1,"lower saturation");
  up;if(brightness_level!==1)$fatal(1,"S5 increase");
  repeat(5)up;if(brightness_level!==3)$fatal(1,"upper saturation");
  down;if(brightness_level!==2)$fatal(1,"release/repress");
  key_down_n=0;key_up_n=0;settle;
  if(brightness_level!==2)$fatal(1,"simultaneous keys changed brightness");
  key_down_n=1;key_up_n=1;settle;
  sw_audio_enable=1;settle;if(!audio_enable)$fatal(1,"audio enable");
  sw_audio_enable=0;settle;if(audio_enable)$fatal(1,"audio mute");
  rst=1;tick;rst=0;settle;if(brightness_level!==3)$fatal(1,"reset restores 100 percent");
  $display("PASS: direct S5/S6 brightness, bounce/hold/repress/chord, saturation, no mode, SW4 audio");$finish;
 end
 initial begin #200000;$fatal(1,"timeout");end
endmodule
