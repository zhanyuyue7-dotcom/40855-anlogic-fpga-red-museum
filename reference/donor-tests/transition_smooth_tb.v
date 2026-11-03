`timescale 1ns/1ps
module transition_smooth_tb;
  reg clk=0,rst=1,vs=1,de=0,start=0,commit=0;
  reg [23:0] rgb=24'hf38107;
  wire [23:0] faded,bypassed;
  wire [5:0] level;
  wire active;
  integer n;
  always #5 clk=~clk;
  transition_fade dut(.clk(clk),.rst(rst),.vs(vs),.de(de),.rgb_in(rgb),
    .start_toggle(start),.commit_toggle(commit),.abort_transition(1'b0),.rgb_out(faded),.fade_level(level),.transition_active(active));
  transition_fade #(.ENABLE(0)) bypass(.clk(clk),.rst(rst),.vs(vs),.de(de),.rgb_in(rgb),
    .start_toggle(start),.commit_toggle(commit),.abort_transition(1'b0),.rgb_out(bypassed));
  task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
  task check;
    input integer wanted;
    reg [7:0] r,g,b;
    begin
      de=1;#1;
      r=(rgb[23:16]*wanted)/32;g=(rgb[15:8]*wanted)/32;b=(rgb[7:0]*wanted)/32;
      if(level!==wanted || faded!=={r,g,b})
        $fatal(1,"smooth expected level=%d RGB=%h got level=%d RGB=%h",wanted,{r,g,b},level,faded);
    end
  endtask
  task frame;
    input integer wanted;
    begin de=0;vs=1;tick;vs=0;tick;check(wanted);end
  endtask
  always @(negedge clk) begin #2;if(bypassed!==rgb) $fatal(1,"bypass changed RGB");end
  initial begin
    repeat(3) tick;rst=0;repeat(4) tick;
    check(32);frame(32); // First image remains fully bright.
    start=1;repeat(4) tick;check(32);
    for(n=31;n>=0;n=n-1) frame(n);
    repeat(4) frame(0); // Missing commit must hold black.
    rgb=24'h2468ac;commit=1;repeat(4) tick;
    frame(0); // Complete black protection frame.
    for(n=1;n<=32;n=n+1) frame(n);
    if(active) $fatal(1,"smooth fade remained active");
    // A new load during fade-in must not jump to full brightness mid-frame.
    start=0;repeat(4) tick;
    for(n=31;n>=0;n=n-1) frame(n);
    commit=0;repeat(4) tick;frame(0);
    for(n=1;n<=8;n=n+1) frame(n);
    start=1;repeat(4) tick;check(8);frame(7);
    $display("PASS: all 33 smooth levels, exact RGB, black wait/guard, bypass and restart continuity");
    $finish;
  end
  initial begin #100000; $fatal(1,"smooth timeout");end
endmodule
