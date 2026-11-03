// Queued arbitration for two single-byte clients, including simultaneous requests.
module w5500_reg_mux2(
 input wire clk,rst,
 input wire a_start,a_write,input wire [15:0] a_addr,input wire [4:0] a_block,input wire [7:0] a_wdata,
 output reg a_done,output reg [7:0] a_rdata,
 input wire b_start,b_write,input wire [15:0] b_addr,input wire [4:0] b_block,input wire [7:0] b_wdata,
 output reg b_done,output reg [7:0] b_rdata,
 output reg out_start,out_write,output reg [15:0] out_addr,output reg [4:0] out_block,
 output reg [7:0] out_wdata,input wire out_done,input wire [7:0] out_rdata
);
 reg [1:0] owner;
 reg ap,bp,turn;
 reg [29:0] ar,br;
 always @(posedge clk)begin
  if(rst)begin owner<=0;ap<=0;bp<=0;turn<=0;ar<=0;br<=0;
   a_done<=0;b_done<=0;a_rdata<=0;b_rdata<=0;out_start<=0;
   out_write<=0;out_addr<=0;out_block<=0;out_wdata<=0;
  end else begin
   a_done<=0;b_done<=0;out_start<=0;
   if(a_start)begin ap<=1;ar<={a_write,a_addr,a_block,a_wdata};end
   if(b_start)begin bp<=1;br<={b_write,b_addr,b_block,b_wdata};end
   if(owner==0)begin
    if(ap && (!bp || !turn))begin
     {out_write,out_addr,out_block,out_wdata}<=ar;out_start<=1;owner<=1;ap<=0;turn<=1;
    end else if(bp)begin
     {out_write,out_addr,out_block,out_wdata}<=br;out_start<=1;owner<=2;bp<=0;turn<=0;
    end
   end else if(out_done)begin
    if(owner==1)begin a_done<=1;a_rdata<=out_rdata;end
    else begin b_done<=1;b_rdata<=out_rdata;end
    owner<=0;
   end
  end
 end
endmodule
