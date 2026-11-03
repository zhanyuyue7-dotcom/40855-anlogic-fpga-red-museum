`timescale 1ns/1ps
module ui_s4_fade_tb;
  reg clk=0, rst=1, vs=1, de=0, trigger=0;
  wire [5:0] fade_level;
  wire visible, transition_active;
  integer i;

  ui_visibility_fade dut(
    .clk(clk), .rst(rst), .vs(vs), .de(de), .trigger_toggle(trigger),
    .fade_level(fade_level), .visible(visible), .transition_active(transition_active)
  );

  always #5 clk=~clk;
  task tick; begin @(posedge clk); #1; end endtask
  task frame_boundary;
    begin
      vs=1; de=0; repeat(2) tick;
      vs=0; repeat(2) tick;
    end
  endtask
  task press_s4;
    begin
      trigger=~trigger; repeat(3) tick;
    end
  endtask

  initial begin
    repeat(3) tick; rst=0; repeat(3) tick;
    if (fade_level !== 6'd32 || !visible) $fatal(1, "UI must start visible");

    press_s4;
    for (i=0; i<40; i=i+1) frame_boundary;
    if (fade_level !== 6'd0 || visible || transition_active)
      $fatal(1, "First S4 press must fade UI out and hold hidden: level=%0d visible=%b", fade_level, visible);
    if (fade_level !== 6'd0) $fatal(1, "Hidden UI moved without a second S4 press");

    press_s4;
    for (i=0; i<40; i=i+1) frame_boundary;
    if (fade_level !== 6'd32 || !visible || transition_active)
      $fatal(1, "Second S4 press must fade UI in and hold visible: level=%0d visible=%b active=%b", fade_level, visible, transition_active);
    $display("PASS: S4 persistent UI visibility toggle, fade-out/fade-in");
    $finish;
  end
  initial begin #200000; $fatal(1, "timeout"); end
endmodule
