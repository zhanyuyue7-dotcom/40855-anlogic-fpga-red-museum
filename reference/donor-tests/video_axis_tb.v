`timescale 1ns/1ps
module video_axis_tb;
  reg clk=0, rst=1, vs=0, de=0;
  reg [23:0] rgb=0;
  wire user, valid, last;
  wire [23:0] data;
  integer frame, line, pixel, errors=0, last_count=0, sof_count=0;
  video_rgb_to_axis_640x480 dut(clk,rst,vs,de,rgb,user,valid,last,data);
  always #5 clk=~clk;
  task step;
    input v;
    input d;
    input [23:0] color;
    input expected_user;
    input expected_last;
    begin
      @(negedge clk); vs=v; de=d; rgb=color;
      @(posedge clk); #1;
      if(valid !== d || user !== expected_user || last !== expected_last || data !== color) begin
        if(errors<6) $display("MISMATCH frame=%0d line=%0d pixel=%0d valid=%b user=%b last=%b expected=%b/%b/%b",frame,line,pixel,valid,user,last,d,expected_user,expected_last);
        errors=errors+1;
      end
      if(last) last_count=last_count+1;
      if(user) sof_count=sof_count+1;
    end
  endtask
  initial begin
    repeat(3) @(negedge clk); rst=0;
    for(frame=0;frame<2;frame=frame+1) begin
      step(1,0,0,0,0); step(1,0,0,0,0); step(0,0,0,0,0);
      for(line=0;line<480;line=line+1) begin
        for(pixel=0;pixel<640;pixel=pixel+1)
          step(0,1,(line*640+pixel),line==0 && pixel==0,pixel==639);
        repeat(8) step(0,0,0,0,0);
      end
    end
    if(last_count!=960 || sof_count!=2) errors=errors+1;
    if(errors) $fatal(1,"FAIL errors=%0d EOL=%0d (expected 960) SOF=%0d (expected 2)",errors,last_count,sof_count);
    $display("PASS: two 640x480 frames; pixel data, valid, 960 EOL and 2 SOF checked");
    $finish;
  end
endmodule
