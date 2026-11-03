`timescale 1ns/1ps
module transition_pipeline_tb;
  reg clk=0,rst=1,vs=1,de=0,start=0,commit=0,ack=0;
  reg [1:0] desired=0;
  wire [1:0] selected;
  wire [5:0] level;
  wire active,ready;
  wire [23:0] rgb;
  integer frame_no, pass;
  reg [1:0] old_idx;
  reg ack_enable=0;
  always #5 clk=~clk;
  transition_buffer_select select_buffer(.clk(clk),.rst(rst),.disp_buf_idx(desired),
    .transition_active(active),.black(level==0),.read_buf_idx(selected));
  transition_commit_guard guard(.clk(clk),.rst(rst),.commit_toggle(commit),
    .disp_buf_idx(selected),.read_req_ack(ack),.vs(vs),.de(de),.ready_toggle(ready));
  transition_fade fade(.clk(clk),.rst(rst),.vs(vs),.de(de),
    .rgb_in(selected==0 ? 24'hff8040 : 24'h4080ff),
    .start_toggle(start),.commit_toggle(ready),.abort_transition(1'b0),.rgb_out(rgb),
    .fade_level(level),.transition_active(active));
  task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
  task frame;
    begin
      de=0;vs=1;repeat(3) tick;vs=0;repeat(5) tick;
      ack=ack_enable;repeat(4) tick;ack=0;repeat(5) tick;
      de=1;tick;
      if(fade.phase==1 && level!=0 && selected!=old_idx)
        $fatal(1,"fast load replaced visible old image before black");
      if(fade.phase==3 && selected!=desired)
        $fatal(1,"fade-in started before new buffer selection");
    end
  endtask
  initial begin
    repeat(4) tick;rst=0;repeat(6) tick;
    if(selected!=0 || level!=32 || active) $fatal(1,"first image not bypassed");
    for(pass=0;pass<2;pass=pass+1) begin
      old_idx=selected;start=~start;repeat(5) tick;
      // New image completes well before fade-out: reader must retain old one.
      desired=1-selected;commit=~commit;repeat(6) tick;
      ack_enable=1;
      for(frame_no=0;frame_no<30;frame_no=frame_no+1) frame;
      ack_enable=0;
      repeat(8) frame;
      if(level!=0 || !active || selected!=desired)
        $fatal(1,"black wait did not survive missing read ACK");
      ack_enable=1;
      repeat(38) frame;
      if(active || level!=32 || selected!=desired)
        $fatal(1,"new image did not finish fade-in");
    end
    $display("PASS: smooth fade + buffer select + guard, both buffers, early commit and stalled ACK");
    $finish;
  end
  initial begin #1000000;$fatal(1,"pipeline timeout");end
endmodule
