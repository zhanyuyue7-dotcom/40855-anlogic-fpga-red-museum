`timescale 1ns/1ps
// Compile with the production vendor FIFO to verify real read-valid latency.
module hxfp_frame_bridge_tb;
 reg net=0,sd=0,video=0;always #10 net=~net;always #5 sd=~sd;always #20 video=~video;
 reg rst=1,begin_req=0,commit_req=0,abort_req=0,pv=0;
 reg[15:0]pixel=16'hf800;
 wire br,cr,pr,fe,hold,owner,req,we,dv;wire[31:0]data;wire[1:0]wi,di;wire[31:0]dc;
 reg ack=0,wready=0,finish=0,vs=0,de=0,readack=0,tfcommit=0;
 integer count=0,i,j;reg memdone=0;
 hxfp_frame_bridge #(.FRAME_PIXELS(16))dut(
 .net_clk(net),.sd_clk(sd),.video_clk(video),.rst(rst),.begin_request(begin_req),.commit_request(commit_req),
 .abort_request(abort_req),.begin_ready(br),.commit_ready(cr),.pixel_valid(pv),.pixel_rgb565(pixel),.pixel_ready(pr),
 .storage_error(1'b0),.frame_error(fe),.boot_active(1'b0),.boot_owns_sd(1'b0),.bmp_busy(1'b0),
 .transition_busy(1'b0),.mem_ready(1'b1),.hold_scheduler(hold),.write_owner(owner),.write_request(req),
 .write_enable(we),.write_data(data),.write_index(wi),.write_ack(ack),.write_fifo_ready(wready),
 .write_finish_toggle(finish),.vs(vs),.de(de),.read_req_ack(readack),.tf_commit_toggle(tfcommit),
 .display_valid(dv),.display_index(di),.displayed_count(dc));
 always @(posedge sd)begin
  if(rst)begin ack<=0;count<=0;end
  else begin
   ack<=req;
   if(we)begin
    if(!wready || !owner)$fatal(1,"write without ownership/readiness");
    if(data!==32'hff000000)$fatal(1,"RGB packing mismatch %h",data);
    count<=count+1;
   end
  end
 end
 task boundary;
  begin @(negedge video);vs=1;repeat(2)@(negedge video);vs=0;repeat(2)@(negedge video);end
 endtask
 initial begin
  #200;rst=0;@(negedge net);begin_req=1;wait(br);@(negedge net);begin_req=0;
  if(!hold || !owner)$fatal(1,"not reserved");
  // Fill the FIFO while the memory sink is stalled, then exercise backpressure.
  wready=0;
  for(i=0;i<16;i=i+1)begin @(negedge net);wait(pr);pv=1;@(negedge net);pv=0;end
  repeat(8)@(negedge sd);if(count!=0)$fatal(1,"write escaped backpressure");
  for(j=0;j<80;j=j+1)begin @(negedge sd);wready=(j%3!=0);end
  wready=1;
  wait(count==16);repeat(12)@(negedge net);
  commit_req=1;
  repeat(15)@(negedge net);if(cr || dv)$fatal(1,"commit before memory drain");
  finish=~finish;repeat(12)@(negedge video);
  if(cr || dv)$fatal(1,"commit before VS boundary");
  boundary();if(!dv)$fatal(1,"bank did not commit");
  if(cr)$fatal(1,"commit before new reader request");
  boundary();@(negedge video);readack=1;repeat(3)@(negedge video);readack=0;
  wait(cr);if(dc!=1 || di!=3)$fatal(1,"display ack wrong");
  @(negedge net);commit_req=0;wait(!hold);
  // Cancelling the next upload must keep the previously displayed bank intact.
  begin_req=1;wait(br);@(negedge net);begin_req=0;
  @(negedge net);abort_req=1;@(negedge net);abort_req=0;
  repeat(30)@(negedge net);
  if(!dv || di!=3 || dc!=1 || cr)$fatal(1,"abort changed visible frame");
  tfcommit=1;repeat(8)@(negedge video);if(dv)$fatal(1,"TF commit did not restore TF source");
  $display("PASS frame bridge: reserve, RGB layout, write drain, VS/read ACK, cancel and TF restore");$finish;
 end
 initial begin #200000;$fatal(1,"frame bridge timeout state=%d",dut.state);end
endmodule
