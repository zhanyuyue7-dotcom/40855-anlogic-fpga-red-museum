`timescale 1ns/1ps
module ui_blend_equivalence_tb;
 reg clk=0;always #5 clk=~clk;
 wire hs,vs,de;wire[23:0]rgb;
 subtitle_osd d(.clk(clk),.rst(1'b1),.hs(1'b0),.vs(1'b0),.de(1'b0),.rgb(24'd0),
 .scene_id(2'd0),.run_state(4'd0),.brightness_level(2'd0),.adjust_mode(1'b0),
 .hs_out(hs),.vs_out(vs),.de_out(de),.rgb_out(rgb),.ui_fade_level(6'd0));
 integer u,o,g,expected;reg[7:0]actual;
 initial begin
  for(g=0;g<=32;g=g+1)for(u=0;u<256;u=u+1)for(o=0;o<256;o=o+1)begin
   expected=(u*(32-g)+o*g)>>5;
   actual=d.blend_channel(u,o,g);
   if(actual!==expected[7:0])$fatal(1,"blend %d %d %d got %d expected %d",u,o,g,actual,expected);
  end
  $display("PASS UI blend: 2162688 exhaustive channel/gain comparisons");$finish;
 end
endmodule
