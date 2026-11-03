`timescale 1ns/1ps
module image_write_address_tb;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,req=0,top_down=0;
 reg [1:0] bank=0;
 wire ack,done,en;
 wire [20:0] addr;
 integer count=0,expected,base;
 frame_fifo_write dut(.rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),
  .Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),.App_rd_busy(1'b0),
  .App_wr_en(en),.App_wr_addr(addr),.write_top_down(top_down),
  .write_req(req),.write_req_ack(ack),.write_finish(done),
  .write_addr_0(21'd0),.write_addr_1(21'd524288),
  .write_addr_2(21'd1048576),.write_addr_3(21'd1572864),
  .write_addr_index(bank),.write_len(21'd307200),.rdusedw(10'd256));
 always @(posedge clk) if(!rst && en)begin
  expected=base+(top_down ? count : ((479-count/640)*640+count%640));
  if(count>=307200 || addr!==expected[20:0])
   $fatal(1,"pixel %0d top_down=%b addr=%h expected=%h",count,top_down,addr,expected);
  count=count+1;
 end
 task frame;
  input down;input [1:0] index;
  begin
   @(negedge clk);top_down=down;bank=index;base=index*524288;count=0;req=1;
   wait(ack);@(negedge clk);req=0;wait(!ack);wait(done);
   @(negedge clk);if(count!=307200)$fatal(1,"wrong frame length %0d",count);
   repeat(5)@(negedge clk);
  end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst=0;
  frame(0,0);frame(1,2);frame(1,3);frame(0,1);
  $display("PASS production frame writer: all 1228800 addresses, BMP bottom-up and HXFP top-down, four banks");$finish;
 end
 initial begin #20000000;$fatal(1,"writer timeout");end
endmodule
