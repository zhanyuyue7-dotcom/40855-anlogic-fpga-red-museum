`timescale 1ns/1ps
module boot_equivalence_tb;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,init=0,valid=0,secend=0,ack=0,wfinish=0;
 reg[7:0]bytein=0;reg[1:0]consumed=0;
 wire areq,breq;wire[31:0]aa,ba;wire awreq,bwreq,awe,bwe;
 wire[31:0]ad,bd;wire[1:0]aidx,bidx,ar,br;wire ao,bo,donea,doneb,aborta,abortb;
 integer i,j,ac=0,bc=0;reg[31:0]gold[0:2047];integer sector=0;
 boot_video_stream_ref #(.SRC_W(16),.SRC_H(16),.START_SECTOR(0))a(
 .clk(clk),.rst(rst),.SD_MISO(1'b1),.sd_init_done(init),.sd_sec_read(areq),.sd_sec_read_addr(aa),
 .sd_sec_read_data(bytein),.sd_sec_read_data_valid(valid),.sd_sec_read_end(secend),
 .write_req(awreq),.write_req_ack(ack),.write_en(awe),.write_data(ad),.write_finish_toggle(wfinish),
 .write_addr_index(aidx),.owns_sd(ao),.ready_toggle(ar),.consumed_toggle(consumed),.stream_done(donea),.stream_abort(aborta));
 boot_video_stream #(.SRC_W(16),.SRC_H(16),.START_SECTOR(0))b(
 .clk(clk),.rst(rst),.SD_MISO(1'b1),.sd_init_done(init),.sd_sec_read(breq),.sd_sec_read_addr(ba),
 .sd_sec_read_data(bytein),.sd_sec_read_data_valid(valid),.sd_sec_read_end(secend),
 .write_req(bwreq),.write_req_ack(ack),.write_en(bwe),.write_data(bd),.write_finish_toggle(wfinish),
 .write_addr_index(bidx),.owns_sd(bo),.ready_toggle(br),.consumed_toggle(consumed),.stream_done(doneb),.stream_abort(abortb));
 always @(posedge clk)begin
  if(awe)begin gold[ac]<=ad;ac<=ac+1;end
  if(bwe)begin
   if(bc>=ac || bd!==gold[bc])$fatal(1,"boot pixel mismatch %d %h expected %h",bc,bd,gold[bc]);
   bc<=bc+1;
  end
 end
 task sendsector;
  input integer number;
  begin
   for(i=0;i<512;i=i+1)begin
    @(negedge clk);valid=1;
    if(number==0)begin
     case(i)
      0:bytein=8'h42;1:bytein=8'h56;2:bytein=8'h50;3:bytein=8'h31;
      4:bytein=16;6:bytein=16;12:bytein=1;17:bytein=2;
      default:bytein=0;
     endcase
    end else bytein=i[7:0];
    @(negedge clk);valid=0;repeat(3)@(negedge clk);
   end
   @(negedge clk);secend=1;@(negedge clk);secend=0;
  end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst=0;init=1;
  wait(areq && breq);sendsector(0);
  wait(awreq && bwreq);ack=1;repeat(10)@(negedge clk);ack=0;
  wait(areq && breq);sendsector(1);
  wait(bc==1024);repeat(12)@(negedge clk);wfinish=1;
  wait(donea && doneb);
  if(ac!=1024 || bc!=1024 || aborta || abortb)$fatal(1,"boot completion incorrect");
  $display("PASS boot BRAM pixel equivalence: complete 2x2 RGB565 enlargement");$finish;
 end
 initial begin #10000000;$fatal(1,"boot timeout ac=%d bc=%d state=%d",ac,bc,b.state);end
endmodule
// The producer gets a simulated sector stream directly; its unused SD master
// has no effect on the stimulus above.
module sd_card_top(input clk,rst,SD_MISO,output SD_nCS,SD_DCLK,SD_MOSI,
 output sd_init_done,input sd_sec_read,input[31:0]sd_sec_read_addr,
 input sd_sec_write,input[31:0]sd_sec_write_addr,input[7:0]sd_sec_write_data,
 output sd_sec_write_data_req,sd_sec_write_end,
 output[7:0]sd_sec_read_data,output sd_sec_read_data_valid,sd_sec_read_end);
 assign SD_nCS=1;assign SD_DCLK=0;assign SD_MOSI=1;
 assign sd_sec_write_data_req=0;assign sd_sec_write_end=0;
endmodule
