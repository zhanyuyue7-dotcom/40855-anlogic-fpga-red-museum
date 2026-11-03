`timescale 1ns/1ps
module image_commit_tb;
  reg clk=0, rst=1, finish_toggle=0;
  reg init_done=0, source_ready=0, scan_done=0, found=0;
  wire display_valid;
  wire [1:0] wr_idx, disp_idx;
  wire transition_start_toggle, display_commit_toggle;
  integer scenario, errors=0;
  sd_card_bmp dut(.clk(clk),.rst(rst),.key_next(1'b1),.key_auto(1'b1),
    .transition_block(1'b0),
`ifndef LAB4_BASELINE
    .emergency_active(1'b0),
`endif
    .bmp_width(16'd640),.bmp_height(16'd480),.display_valid(display_valid),
    .write_finish_toggle(finish_toggle),.write_buf_idx(wr_idx),.disp_buf_idx(disp_idx),
`ifndef LAB4_BASELINE
    .transition_start_toggle(transition_start_toggle),
    .display_commit_toggle(display_commit_toggle),
`endif
    .write_req_ack(1'b0),.SD_MISO(1'b1));
  always #5 clk=~clk;
  task tick;
    begin @(posedge clk); #1; @(negedge clk); end
  endtask
  initial begin
    // Isolate the real controller at its BMP reader / card-init boundaries.
    // write_finish_toggle still traverses the production CDC synchronizer.
    force dut.sd_init_done=init_done;
    force dut.bmp_ready=source_ready;
    force dut.scan_done=scan_done;
    force dut.scan_found_valid=found;
    force dut.scan_found_sector=32'd100;
    for(scenario=0;scenario<6;scenario=scenario+1) begin
      rst=1; init_done=0; source_ready=0; scan_done=0; found=0; finish_toggle=0;
      repeat(4) tick;
      rst=0; init_done=1; source_ready=1;
      repeat(2) tick;
      found=1; tick; found=0; scan_done=1;
      while(!dut.load_start_pulse) tick;
      if(!dut.load_busy) $fatal(1,"fixture did not start a real image load");
      // Production reader consumes the registered start on the next edge.
      if(scenario>=3) tick;
      source_ready=0; repeat(4) tick;
      if(display_valid) $fatal(1,"committed before either completion");
      if((scenario%3)==0) begin
        source_ready=1; repeat(5) tick;
        if(display_valid) $fatal(1,"source completion alone committed image");
        finish_toggle=1;
      end else if((scenario%3)==1) begin
        finish_toggle=1; repeat(6) tick;
        if(display_valid) $fatal(1,"memory completion alone committed image");
        source_ready=1;
      end else begin
        finish_toggle=1; repeat(2) tick; source_ready=1;
      end
      repeat(8) tick;
      if(!display_valid || dut.load_busy) begin
        $display("FAIL scenario=%0d valid=%b busy=%b",scenario,display_valid,dut.load_busy);
        errors=errors+1;
      end
`ifndef LAB4_BASELINE
      if (transition_start_toggle !== 1'b0 || display_commit_toggle !== 1'b0)
        $fatal(1,"first image unexpectedly generated a transition event");
      if (scenario == 0) begin
        // A later image load must start the fade, and its real buffer commit
        // must produce the matching completion event.
        force dut.next_req_pending = 1'b1;
        scan_done = 1;
        source_ready = 1;
        tick;
        release dut.next_req_pending;
        while (!dut.load_start_pulse) tick;
        if (transition_start_toggle === 1'b0)
          $fatal(1,"subsequent image load did not toggle transition start");
        force dut.source_done_seen = 1'b1;
        force dut.write_done_seen = 1'b1;
        repeat(2) tick;
        release dut.source_done_seen;
        release dut.write_done_seen;
        if (!display_valid || dut.load_busy)
          $fatal(1,"subsequent image did not commit busy=%b source=%b write=%b bmp=%b finish=%b sync=%b",
            dut.load_busy, dut.source_done_seen, dut.write_done_seen, dut.bmp_ready,
            dut.write_finish_pulse, dut.wrfin_tgl_sync[2]);
        if (display_commit_toggle === 1'b0)
          $fatal(1,"subsequent image commit did not toggle transition commit");
      end
`endif
    end
    if(errors) $fatal(1,"FAIL completion orderings=%0d",errors);
    $display("PASS: 6 cases: three completion orders x immediate/registered reader acceptance; no premature commit");
    $finish;
  end
endmodule
