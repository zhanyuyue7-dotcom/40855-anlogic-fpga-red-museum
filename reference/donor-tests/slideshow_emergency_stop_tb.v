`timescale 1ns/1ps
// Real scheduler/CDC/keys; only reader and SD boundary outputs are mocked.
module slideshow_emergency_stop_tb;
  reg clk=0,rst=1,emergency=0,key_next=1,key_auto=1;
  reg init_done=0,ready=0,scan_done=0,found=0,finish_toggle=0;
  reg transition_block=0;
  wire valid,busy,start,commit;
  integer loads=0,saved_loads;
  reg old_start;
  sd_card_bmp #(.CLK_FREQ_HZ(1000)) dut(
    .clk(clk),.rst(rst),.key_next(key_next),.key_auto(key_auto),
    .emergency_active(emergency),.bmp_width(16'd640),.bmp_height(16'd480),
    .transition_block(transition_block),
    .display_valid(valid),.load_busy(busy),.write_finish_toggle(finish_toggle),
    .transition_start_toggle(start),.display_commit_toggle(commit),
    .write_req_ack(1'b0),.SD_MISO(1'b1));
  always #5 clk=~clk;
  always @(posedge clk) if(!rst && dut.load_start_pulse) loads=loads+1;
  task tick; begin @(posedge clk); #1; @(negedge clk); end endtask
  task auto_key; begin key_auto=0;repeat(26) tick;key_auto=1;repeat(26) tick;end endtask
  task next_key; begin key_next=0;repeat(26) tick;key_next=1;repeat(26) tick;end endtask
  task finish_load; begin
    ready=1;finish_toggle=~finish_toggle;repeat(8) tick;
    if(busy || !valid) $fatal(1,"in-flight image did not commit safely");
  end endtask
  task stopped; begin
    if(dut.auto_play_en!==0 || dut.auto_cnt!==0 || dut.next_req_pending!==0)
      $fatal(1,"emergency must clear auto mode, timer and queued next request");
  end endtask
  initial begin
    force dut.sd_init_done=init_done;force dut.bmp_ready=ready;
    force dut.scan_done=scan_done;force dut.scan_found_valid=found;
    force dut.scan_found_sector=32'd100;
    repeat(4) tick;rst=0;init_done=1;ready=1;repeat(3) tick;
    repeat(4) begin found=1;tick;found=0;tick;end
    scan_done=1;
    wait(dut.load_start_pulse);@(negedge clk);ready=0;repeat(4) tick;
    finish_load;
    if(start || commit) $fatal(1,"first image must not start a fade");

    // M5 regression: a second KEY2 may be queued while E2 is still fading,
    // but its producer write must wait until the old read buffer is released.
    transition_block=1;
    next_key;
    repeat(40) tick;
    if(!dut.next_req_pending || dut.load_start_pulse || busy)
      $fatal(1,"queued KEY2 started a write while transition guard was active");
    transition_block=0;
    wait(dut.load_start_pulse);
    @(negedge clk);ready=0;repeat(4) tick;
    finish_load;

    auto_key;
    if(!dut.auto_play_en) $fatal(1,"KEY4 did not enable auto");
    wait(dut.load_start_pulse);@(negedge clk);ready=0;repeat(4) tick;
    next_key;
    if(!dut.next_req_pending) $fatal(1,"fixture did not queue KEY2");
    old_start=start;
    #2;emergency=1;repeat(5) tick;stopped;
    ready=1;repeat(5) tick;
    if(!busy) $fatal(1,"emergency bypassed two-sided commit contract");
    finish_toggle=~finish_toggle;repeat(8) tick;stopped;
    if(busy || !valid || start!=old_start)
      $fatal(1,"emergency lost in-flight image or launched a queued load");
    saved_loads=loads;
    next_key;auto_key;stopped;
    repeat(1100) tick;stopped;
    if(loads!=saved_loads) $fatal(1,"new load started during emergency");
    #2;emergency=0;repeat(1100) tick;stopped;
    if(loads!=saved_loads) $fatal(1,"autoplay resumed after emergency");
    next_key;
    if(!busy || start==old_start || dut.auto_play_en) $fatal(1,"manual restart failed");
    ready=0;repeat(4) tick;finish_load;
    auto_key;
    if(!dut.auto_play_en) $fatal(1,"explicit auto restart failed");
    while(dut.auto_cnt<997) tick;
    emergency=1;repeat(3) tick;
    if(dut.load_start_pulse || busy) $fatal(1,"auto expiry beat emergency stop");
    stopped;
    $display("PASS: real keys, queue cancellation, dual completion, key inhibit, no auto resume, restart, auto-tick collision");
    $finish;
  end
  initial begin #1000000;$fatal(1,"slideshow emergency timeout");end
endmodule
