`timescale 1ns/1ps
// Production fade/reader guard + debounced scene controller. Small synthetic
// blanking intervals keep simulation fast; M3/E1 tests check full-frame pixels.
module transition_preemption_tb;
  parameter ENABLE=1;
  parameter ABORT_CONNECTED=1; // negative control for the missing-termination bug
  reg clk=0,rst=1,vs=1,de=0,start=0,commit=0,ack=0;
  reg key_n=1,emergency=1,clear_sw=0,unknown_background=0;
  reg [1:0] desired=0;
  wire [1:0] selected,scene;
  wire [5:0] level;
  wire active,ready;
  wire [23:0] faded_preview,scene_rgb,rgb;
  wire [23:0] background=unknown_background ? 24'hxxxxxx :
      selected==0 ? 24'hcc8844 : 24'h4488cc;
  integer point,exit_mode,stall,f;
  reg [23:0] before_rgb;
  transition_buffer_select select_buffer(.clk(clk),.rst(rst),.disp_buf_idx(desired),
    .transition_active(active),.black(level==0),.read_buf_idx(selected));
  transition_commit_guard guard(.clk(clk),.rst(rst),.commit_toggle(commit),
    .disp_buf_idx(selected),.read_req_ack(ack),.vs(vs),.de(de),.ready_toggle(ready));
  transition_fade #(.ENABLE(ENABLE)) fade(.clk(clk),.rst(rst),.vs(vs),.de(de),
    .rgb_in(background),.start_toggle(start),.commit_toggle(ready),
    .abort_transition(ABORT_CONNECTED && scene==2),.rgb_out(faded_preview),.fade_level(level),.transition_active(active));
  scene_video #(.DEBOUNCE_CYCLES(2),.NOTICE_HOLD_FRAMES(3),.EMERGENCY_HOLD_FRAMES(3))
    video(.clk(clk),.rst(rst),.vs(vs),.de(de),.background_rgb(background),
      .key_event_n(key_n),.sw_emergency(emergency),.sw_clear(clear_sw),
      .rgb(scene_rgb),.scene_id(scene));
  transition_rgb_scale #(.ENABLE(ENABLE)) composite_scale(
    .de(de),.rgb_in(scene_rgb),.scale(level),.bypass(scene!=0),.rgb_out(rgb));
  always #5 clk=~clk;
  task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
  task frame;begin
    de=0;vs=1;repeat(4) tick;vs=0;repeat(6) tick;
    ack=!stall;repeat(4) tick;ack=0;repeat(5) tick;
    de=1;tick;
  end endtask
  task full;begin
    if(active!==0 || level!==32 || faded_preview!==background ||
        (scene==0 && rgb!==background))
      $fatal(1,"stale fade after emergency point=%0d exit=%0d stall=%0d",point,exit_mode,stall);
  end endtask
  task reset_case;begin
    rst=1;vs=1;de=0;start=0;commit=0;desired=0;ack=0;
    key_n=1;emergency=1;clear_sw=0;unknown_background=0;
    repeat(4) tick;rst=0;repeat(12) tick;de=1;tick;full;
  end endtask
  // Literal bypass includes reset, blanking and active event presentation.
  always @(negedge clk) if(!ENABLE &&
      (faded_preview!==background || rgb!==scene_rgb))
    $fatal(1,"compile-time bypass altered RGB");
  initial begin
    for(point=0;point<3;point=point+1)
      for(exit_mode=0;exit_mode<2;exit_mode=exit_mode+1)
        for(stall=0;stall<2;stall=stall+1) begin
          reset_case;
          start=~start;repeat(6) tick;
          if(point>0) begin
            desired=1;commit=~commit;repeat(6) tick;
            // Reach black midpoint; a stalled ACK is deliberately unbounded.
            if(ENABLE) begin
              repeat(32) frame;
              if(level!==0) $fatal(1,"midpoint fixture did not reach black");
            end else repeat(32) frame;
          end
          if(point==2) begin
            // To reach the actual end, temporarily allow reader acceptance.
            // Then stall reads again at emergency arrival if requested.
            f=stall;stall=0;
            if(ENABLE) begin
              while(!(fade.phase==3 && level==31)) frame;
            end else repeat(34) frame;
            stall=f;
          end
          before_rgb=rgb;
          key_n=0;repeat(10) tick;key_n=1;repeat(10) tick;
          if(scene!==0 || rgb!==before_rgb)
            $fatal(1,"event tore visible frame before scene commit");
          frame;
          if(scene!==2 || rgb!==24'hc82020) $fatal(1,"emergency was blocked by fade/storage");
          full;
          unknown_background=1;tick;
          if(rgb!==24'hc82020) $fatal(1,"emergency leaked unknown background");
          frame;
          if(scene!==2 || rgb!==24'hc82020) $fatal(1,"emergency ended early");
          // Even a start/commit arriving under the alert is consumed, not queued.
          start=~start;commit=~commit;repeat(8) tick;
          if(active || level!==32) $fatal(1,"hidden fade restarted under emergency");
          if(exit_mode) begin clear_sw=1;repeat(10) tick;end
          unknown_background=0;
          frame;
          if(!exit_mode) frame;
          if(scene!==0) $fatal(1,"scene did not return on clear/expiry");
          full;
          // Late writer commit after return must not revive a cancelled fade.
          desired=1-desired;commit=~commit;repeat(8) tick;
          repeat(6) begin frame;full;end
          // A new manual/automatic load is allowed to start a fresh fade.
          start=~start;repeat(6) tick;frame;
          if(ENABLE && (!active || level!==31))
            $fatal(1,"fresh load failed to start from full brightness");
          $display("PASS matrix ENABLE=%0d point=%0d exit=%0d stalled_ACK=%0d",ENABLE,point,exit_mode,stall);
        end
    $display("PASS: start/black/end, expiry/clear, stalled reader, full return, late commits, fresh restart and bypass");
    $finish;
  end
  initial begin #10000000;$fatal(1,"preemption matrix timeout");end
endmodule
