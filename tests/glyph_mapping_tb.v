`timescale 1ns/1ps
module glyph_mapping_tb;
 reg clk=0;always #5 clk=~clk;
 reg [5:0] glyph=0;reg [4:0] row=0;
 wire [15:0] a,b;wire [23:0] c,d;
 integer g,r;
 osd_glyph_rom u0(clk,glyph,row[3:0],a);
 osd_glyph_rom_bram_ref u1(clk,glyph,row[3:0],b);
 osd_glyph_rom_24 u2(clk,glyph,row,c);
 osd_glyph_rom_24_bram_ref u3(clk,glyph,row,d);
 initial begin
  for(g=0;g<64;g=g+1)for(r=0;r<32;r=r+1)begin
   @(negedge clk);glyph=g;row=r;
   @(posedge clk);#1;
   if(a!==b || c!==d)$fatal(1,"glyph/row %0d/%0d differs",g,r);
  end
  $display("PASS LUT/BRAM glyph equivalence: all glyph/row addresses, same latency");$finish;
 end
endmodule
