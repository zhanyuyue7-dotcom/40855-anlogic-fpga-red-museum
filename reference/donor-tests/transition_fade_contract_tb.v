`timescale 1ns/1ps
module transition_fade_contract_tb;
  reg clk=0,rst=1,vs=1,de=0,start=0,commit=0;
  reg [23:0] rgb=24'hf38107;
  wire [23:0] faded,bypassed;
  wire [5:0] level;
  wire active;
  always #5 clk=~clk;
  transition_fade #(.SMOOTH(0)) dut(.clk(clk),.rst(rst),.vs(vs),.de(de),.rgb_in(rgb),
    .start_toggle(start),.commit_toggle(commit),.abort_transition(1'b0),.rgb_out(faded),.fade_level(level),.transition_active(active));
  transition_fade #(.SMOOTH(0), .ENABLE(0)) bypass(.clk(clk),.rst(rst),.vs(vs),.de(de),.rgb_in(rgb),
    .start_toggle(start),.commit_toggle(commit),.abort_transition(1'b0),.rgb_out(bypassed));
  task tick; begin @(posedge clk);#1;@(negedge clk);end endtask
  task frame;
    input [1:0] expected;
    begin
      de=0;vs=1;tick;vs=0;tick;de=1;#1;
      if(level!==expected) $fatal(1,"one-frame default expected level %d got %d",expected,level);
    end
  endtask
  // Compile-time bypass must be literal passthrough, including reset/blanking.
  always @(negedge clk) begin
    #2;
    if(bypassed!==rgb) $fatal(1,"ENABLE=0 changed RGB during reset/blanking");
  end
  initial begin
    repeat(3) tick;rst=0;repeat(4) tick;
    frame(3);frame(3); // First image has no start notification.
    start=1;repeat(4) tick;
    frame(2);if(faded!==24'h794003) $fatal(1,"half channel scaling");
    frame(1);if(faded!==24'h3c2001) $fatal(1,"quarter channel scaling");
    frame(0);frame(0);frame(0);
    rgb=24'h2468ac;commit=1;repeat(4) tick;
    frame(0); // One complete frame after commit remains black.
    frame(1);if(faded!==24'h091a2b) $fatal(1,"new image quarter scaling");
    frame(2);frame(3);
    if(active) $fatal(1,"fade did not finish");
    $display("PASS: default one-frame levels, first-image bypass, black guard, exact RGB bypass");
    $finish;
  end
  initial begin #100000; $fatal(1,"contract timeout");end
endmodule
