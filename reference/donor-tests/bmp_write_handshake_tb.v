`timescale 1ns/1ps
module bmp_write_handshake_tb;
  reg clk=0, rst=1, load_start=0, ack=0, valid=0, sec_end=0;
  reg [7:0] data=0;
  wire req, sec_read, pixels, ready;
  wire [3:0] state_code;
  integer i;
  always #5 clk=~clk;
  bmp_read dut(.clk(clk),.rst(rst),.ready(ready),
    .scan_start(1'b0),.scan_start_sector(32'd0),.scan_max_sector(32'd0),
    .scan_target_count(3'd1),.load_start(load_start),.load_sector(32'd100),
    .sd_init_done(1'b1),.state_code(state_code),.bmp_width(16'd640),.bmp_height(16'd480),
    .write_req(req),.write_req_ack(ack),.sd_sec_read(sec_read),
    .sd_sec_read_data(data),.sd_sec_read_data_valid(valid),.sd_sec_read_end(sec_end),
    .bmp_data_wr_en(pixels));
  task tick; begin @(posedge clk); #1; @(negedge clk); end endtask
  function [7:0] header;
    input integer n;
    begin
      case(n)
        0:header="B"; 1:header="M";
        2:header=8'h36; 3:header=8'h10; 4:header=8'h0e;
        10:header=54;
        18:header=8'h80; 19:header=8'h02;
        22:header=8'he0; 23:header=8'h01;
        28:header=24;
        default:header=0;
      endcase
    end
  endfunction
  initial begin
    repeat(4) tick; rst=0; tick;
    load_start=1; tick; load_start=0;
    while(!sec_read) tick;
    for(i=0;i<512;i=i+1) begin valid=1;data=header(i);tick;end
    valid=0;sec_end=1;tick;sec_end=0;tick;
    if(!req) $fatal(1,"header did not request a frame write");
    repeat(4) tick;
    // The asynchronous writer can keep ACK (and FIFO reset) asserted
    // after the request drops. Do not start a payload read during this gap.
    #2;ack=1;
    while(req) tick;
    repeat(20) begin
      tick;
      if(sec_read || pixels) $fatal(1,"payload started while writer ACK/reset was still asserted");
    end
    #3;ack=0;
    repeat(6) tick;
    if(!sec_read || req) $fatal(1,"payload did not start after synchronized ACK release");
    $display("PASS: BMP waits for asynchronous writer ACK assertion and release before payload");
    $finish;
  end
  initial begin #100000; $fatal(1,"write handshake timeout"); end
endmodule
