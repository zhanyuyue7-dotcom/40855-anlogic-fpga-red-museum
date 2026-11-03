`timescale 1ns/1ps
module w5500_image_udp_tb;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,enable=0;
 wire start,wr;wire[15:0]addr;wire[4:0]block;wire[7:0]wdata;
 reg done=0;reg[7:0]rdata=0;
 wire rxstart,rxvalid,rxend;wire[7:0]rxdata;wire[47:0]peer;
 wire txready;reg txvalid=0;reg[7:0]txdata=0;reg txlast=0;
 wire[31:0]received,sent;wire error;
 reg [7:0] regs[0:255],rx[0:2047],tx[0:2047];
 integer i,count=0,txidx=0,cycles=0;
 reg active=0,send_done=0;
 reg[15:0]ptr=16'h07f8;
 w5500_image_udp #(.POLL_CYCLES(12))dut(
 .clk(clk),.rst(rst),.enable(enable),.xfer_start(start),.xfer_write(wr),.xfer_addr(addr),
 .xfer_block(block),.xfer_wdata(wdata),.xfer_done(done),.xfer_rdata(rdata),
 .rx_ready(1'b1),.rx_start(rxstart),.rx_valid(rxvalid),.rx_end(rxend),.rx_data(rxdata),.rx_peer(peer),
 .tx_valid(txvalid),.tx_data(txdata),.tx_last(txlast),.tx_peer(48'hc0a800645a12),.tx_ready(txready),
 .packets_received(received),.packets_sent(sent),.error(error));
 always @(posedge clk)begin
  done<=0;cycles<=cycles+1;
  if(start)begin
   done<=1;
   if(wr)begin
    if(block==9)begin
     regs[addr]<=wdata;
     if(addr==1)begin
      regs[1]<=0;
      if(wdata==8'h40)begin regs[38]<=0;regs[39]<=0;end
      if(wdata==8'h20)begin regs[2]<=8'h10;send_done<=1;end
     end
     if(addr==2)regs[2]<=regs[2]&~wdata;
    end else if(block==10)tx[addr&2047]<=wdata;
    else $fatal(1,"bad write block");
   end else begin
    if(block==9)rdata<=regs[addr];
    else if(block==11)rdata<=rx[addr&2047];
    else $fatal(1,"bad read block");
   end
  end
  if(rxstart)begin
   if(active)$fatal(1,"overlapping datagram");
   active<=1;
   if(peer!==48'hc0a800645a12)$fatal(1,"wrong peer %h",peer);
  end
  if(rxvalid)begin
   if(!active || rxdata!==count[7:0])$fatal(1,"bad RX byte %d %h",count,rxdata);
   count<=count+1;
  end
  if(rxend)begin
   if(count!=40)$fatal(1,"wrong datagram length");
   active<=0;
  end
  if(txready)begin
   txidx<=txidx+1;
   if(txidx==35)begin txvalid<=0;txlast<=0;end
   else begin txdata<=txidx+1;txlast<=txidx==34;end
  end
  if(cycles>20000)$fatal(1,"transport timeout state %d count %d",dut.state,count);
 end
 initial begin
  for(i=0;i<256;i=i+1)regs[i]=0;
  for(i=0;i<2048;i=i+1)begin rx[i]=0;tx[i]=0;end
  regs[32]=8'h08;regs[33]=0;regs[36]=8'h07;regs[37]=8'hfa;
  regs[40]=ptr[15:8];regs[41]=ptr[7:0];regs[38]=0;regs[39]=48;
  rx[ptr]=192;rx[(ptr+1)&2047]=168;rx[(ptr+2)&2047]=0;rx[(ptr+3)&2047]=100;
  rx[(ptr+4)&2047]=8'h5a;rx[(ptr+5)&2047]=8'h12;rx[(ptr+6)&2047]=0;rx[(ptr+7)&2047]=40;
  for(i=0;i<40;i=i+1)rx[(ptr+8+i)&2047]=i;
  repeat(4)@(negedge clk);rst=0;enable=1;
  wait(received==1);repeat(15)@(negedge clk);
  txvalid=1;txdata=0;
  wait(sent==1);repeat(5)@(negedge clk);
  if({regs[40],regs[41]}!==16'h0828)$fatal(1,"RX pointer not retired");
  if({regs[36],regs[37]}!==16'h081e)$fatal(1,"TX pointer wrong");
  for(i=0;i<36;i=i+1)if(tx[(2042+i)&2047]!==i[7:0])$fatal(1,"TX byte %d got %h",i,tx[(2042+i)&2047]);
  if({regs[12],regs[13],regs[14],regs[15],regs[16],regs[17]}!==48'hc0a800645a12)$fatal(1,"ACK target wrong");
  if(error)$fatal(1,"unexpected transport error");
  $display("PASS W5500 image UDP: ring wrap, peer routing, 40 RX and 36 TX bytes");$finish;
 end
endmodule
