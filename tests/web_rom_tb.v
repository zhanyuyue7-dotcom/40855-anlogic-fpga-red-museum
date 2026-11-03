`timescale 1ns/1ps
module web_rom_tb;
 reg [11:0] address=0;
 wire [7:0] data;
 reg [7:0] expected[0:2070];
 integer i;
 // Override path for Icarus, which uses cwd; production TD uses source dir.
 w5500_web_rom #(.INIT_FILE("src/user_source/hdl_source/network/w5500_web_response.hex"))dut(address,data);
 initial begin
  $readmemh("src/user_source/hdl_source/network/w5500_web_response.hex",expected);
  for(i=0;i<2071;i=i+1)begin
   address=i;#1;
   if((^data)===1'bx || data!==expected[i])$fatal(1,"HTTP ROM missing byte %0d",i);
  end
  if(expected[0]!=8'h48 || expected[1]!=8'h54)$fatal(1,"bad HTTP signature");
  $display("PASS HTTP ROM: all 2071 response bytes present");$finish;
 end
endmodule
