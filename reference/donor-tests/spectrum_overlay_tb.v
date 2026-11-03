`timescale 1ns/1ps
module spectrum_overlay_tb;
  reg clk=0, rst=1, hs=0, vs=1, de=0;
  reg [23:0] background=24'h112233;
  reg [1:0] scene=0;
  reg spectrum_enable=0;
  wire hs_out,vs_out,de_out;
  wire [23:0] rgb_out;
  integer red_count, orange_count, bg_count, top_red_count;
  integer row, col;

  spectrum_overlay #(
    .VIDEO_WIDTH(20), .VIDEO_HEIGHT(8), .BAR_COUNT(2), .FRAME_COUNT(2),
    .FRAME_HZ_DIV(1), .HEIGHT_FILE("tests/spectrum_overlay_test.hex")
  ) dut(
    .clk(clk),.rst(rst),.hs(hs),.vs(vs),.de(de),
    .background_rgb(background),.scene_id(scene),.spectrum_enable(spectrum_enable),
    .hs_out(hs_out),.vs_out(vs_out),.de_out(de_out),.rgb_out(rgb_out)
  );
  always #5 clk=~clk;
  task tick;
    begin @(posedge clk); #1; end
  endtask
  task frame_start;
    begin
      vs=1; de=0; repeat(2) tick;
      vs=0; de=0; tick;
    end
  endtask
  task active_frame;
    begin
      for (row=0; row<8; row=row+1) begin
        de=1;
        for (col=0; col<20; col=col+1) begin
          tick;
          if (rgb_out===24'hde5251) begin
            red_count=red_count+1;
            if (row<4) top_red_count=top_red_count+1;
          end else if (rgb_out===24'hde574f)
            orange_count=orange_count+1;
          else if (rgb_out===background)
            bg_count=bg_count+1;
        end
        de=0; tick;
      end
    end
  endtask
  initial begin
    repeat(3) tick; rst=0; repeat(2) tick;
    // Disabled and alert scenes must be a transparent bypass.
    de=1; tick;
    if (rgb_out!==background || hs_out!==hs || vs_out!==vs || de_out!==de)
      $fatal(1,"disabled spectrum is not bypass");
    de=0; tick;
    scene=1; spectrum_enable=1; de=1; tick;
    if (rgb_out!==background) $fatal(1,"alert scene was overlaid");
    de=0; tick; spectrum_enable=0; scene=0;

    spectrum_enable=1;
    frame_start;
    red_count=0; orange_count=0; bg_count=0; top_red_count=0;
    active_frame;
    if (dut.frame_index!==0) $fatal(1,"first spectrum frame must start at zero");
    if (red_count==0 || top_red_count!=0 || orange_count!=0)
      $fatal(1,"frame 0 geometry/color wrong red=%0d top_red=%0d orange=%0d",red_count,top_red_count,orange_count);

    red_count=0; orange_count=0; bg_count=0; top_red_count=0;
    frame_start;
    active_frame;
    if (dut.frame_index!==1) $fatal(1,"frame did not advance at frame boundary");
    if (red_count==0 || orange_count==0 || top_red_count!=0)
      $fatal(1,"frame 1 geometry/color wrong red=%0d orange=%0d top_red=%0d",red_count,orange_count,top_red_count);

    spectrum_enable=0; de=1; tick;
    if (rgb_out!==background) $fatal(1,"spectrum disable did not restore background");
    $display("PASS: spectrum bypass, scene priority, bottom-aligned bars, palette, frame advance");
    $finish;
  end
  initial begin #1000000; $fatal(1,"spectrum overlay timeout"); end
endmodule
