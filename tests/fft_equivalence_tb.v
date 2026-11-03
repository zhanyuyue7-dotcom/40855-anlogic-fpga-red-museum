`timescale 1ns/1ps
module fft_equivalence_tb;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,sv=0;reg signed[15:0]l=0,r=0;
 wire a_ready,b_ready,av,bv;wire[511:0]ah,bh;wire a_busy,b_busy;
 reg[511:0]golden;reg got_a=0,got_b=0;
 integer i,k;real phase;
 spectrum_fft_1024_ref a(.clk(clk),.rst(rst),.sample_valid(sv),.sample_left(l),.sample_right(r),
 .sample_ready(a_ready),.snapshot_valid(av),.snapshot_heights(ah),.busy(a_busy));
 spectrum_fft_1024 b(.clk(clk),.rst(rst),.sample_valid(sv),.sample_left(l),.sample_right(r),
 .sample_ready(b_ready),.snapshot_valid(bv),.snapshot_heights(bh),.busy(b_busy));
 always @(posedge clk)begin
  if(av)begin golden<=ah;got_a<=1;end
  if(bv)begin
   if(!got_a || bh!==golden)$fatal(1,"FFT optimized result mismatch");
   got_b<=1;
  end
 end
 initial begin
  repeat(5)@(negedge clk);rst=0;
  for(k=0;k<3;k=k+1)begin
   got_a=0;got_b=0;
   for(i=0;i<1024;i=i+1)begin
    @(negedge clk);sv=1;
    if(k==0)begin l=0;r=0;end
    else begin phase=6.283185307179586*i*(k==1?32:73)/1024.0;
     l=$rtoi(18000*$sin(phase))+2000;r=-l;
    end
    @(negedge clk);sv=0;repeat(518)@(negedge clk);
   end
   wait(got_b);repeat(10)@(negedge clk);
  end
  $display("PASS FFT bit-exact equivalence: silence, stereo antiphase tones, DC offset");$finish;
 end
 initial begin #50000000;$fatal(1,"FFT equivalence timeout");end
endmodule
