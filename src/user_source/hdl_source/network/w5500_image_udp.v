// Socket 2 UDP transport for HXFP. No physical-packet success is inferred here.
// RX pointers wrap in the configured 2 KiB buffer; ACKs return to the peer's
// source port, not the device's listening port. One register transaction in flight.
module w5500_image_udp #(
    parameter [15:0] PORT=5002,
    parameter integer POLL_CYCLES=50000
)(
    input wire clk,rst,enable,
    output reg xfer_start,xfer_write,
    output reg [15:0] xfer_addr,
    output reg [4:0] xfer_block,
    output reg [7:0] xfer_wdata,
    input wire xfer_done,input wire [7:0] xfer_rdata,
    input wire rx_ready,
    output reg rx_start,rx_valid,rx_end,
    output reg [7:0] rx_data,
    output reg [47:0] rx_peer,
    input wire tx_valid,input wire [7:0] tx_data,input wire tx_last,
    input wire [47:0] tx_peer,output reg tx_ready,
    output reg [31:0] packets_received,packets_sent,
    output reg error
);
    localparam [5:0] INIT=0,INIT_NEXT=1,CR=2,CR_CHECK=3,IDLE=4,
        SIZE_H=5,SIZE_L=6,SIZE_H2=7,SIZE_L2=8,RD_H=9,RD_L=10,
        HEADER=11,HEADER_NEXT=12,VALIDATE=13,START=14,RXBYTE=15,
        RXNEXT=16,RD_SET_H=17,RD_SET_L=18,RECV=19,RECV_DONE=20,
        TX_FREE_H=21,TX_FREE_L=22,TX_DEST=23,TX_DEST_NEXT=24,
        TX_PTR_H=25,TX_PTR_L=26,TXBYTE=27,TXNEXT=28,TX_SET_H=29,
        TX_SET_L=30,TX_SEND=31,TX_POLL=32,TX_POLL_NEXT=33,TX_ADV=34,WAIT_IO=63;
    reg [5:0] state,return_state,after_cr;
    reg [31:0] poll_count,timeout_count;
    reg [2:0] cfg_index,hdr_index,dest_index;
    reg [7:0] high_byte,second_high,last_read;
    reg [15:0] available,rx_pointer,tx_pointer,payload_length,offset,next_pointer;
    reg [15:0] tx_free;
    reg [47:0] destination;
    reg discard;
    localparam [4:0] SREG=5'd9,STX=5'd10,SRX=5'd11;
    task transaction;
        input wr; input [15:0] addr; input [4:0] blk; input [7:0] data; input [5:0] next_state;
        begin
            xfer_start<=1; xfer_write<=wr; xfer_addr<=addr; xfer_block<=blk;
            xfer_wdata<=data; return_state<=next_state; state<=WAIT_IO;
        end
    endtask
    always @(posedge clk) begin
        if(rst) begin
            state<=INIT;return_state<=INIT;after_cr<=IDLE;
            xfer_start<=0;xfer_write<=0;xfer_addr<=0;xfer_block<=0;xfer_wdata<=0;
            rx_start<=0;rx_valid<=0;rx_end<=0;rx_data<=0;rx_peer<=0;tx_ready<=0;
            poll_count<=0;timeout_count<=0;cfg_index<=0;hdr_index<=0;dest_index<=0;
            high_byte<=0;second_high<=0;last_read<=0;available<=0;rx_pointer<=0;tx_pointer<=0;
            payload_length<=0;offset<=0;next_pointer<=0;tx_free<=0;destination<=0;discard<=0;
            packets_received<=0;packets_sent<=0;error<=0;
        end else begin
            xfer_start<=0;rx_start<=0;rx_valid<=0;rx_end<=0;tx_ready<=0;
            if(state==IDLE || state==INIT || state==TX_POLL) timeout_count<=0;
            else timeout_count<=timeout_count+1'b1;
            case(state)
                INIT: if(enable) begin
                    case(cfg_index)
                        0:transaction(1,16'h001e,SREG,2,INIT_NEXT);
                        1:transaction(1,16'h001f,SREG,2,INIT_NEXT);
                        2:transaction(1,16'h0004,SREG,PORT[15:8],INIT_NEXT);
                        3:transaction(1,16'h0005,SREG,PORT[7:0],INIT_NEXT);
                        4:transaction(1,16'h0000,SREG,2,INIT_NEXT);
                        default:begin after_cr<=IDLE;transaction(1,16'h0001,SREG,1,CR);end
                    endcase
                end
                INIT_NEXT:begin cfg_index<=cfg_index+1'b1;state<=INIT;end
                CR:transaction(0,16'h0001,SREG,0,CR_CHECK);
                CR_CHECK:if(last_read==0)state<=after_cr;else state<=CR;
                IDLE:begin
                    if(tx_valid)begin destination<=tx_peer;state<=TX_FREE_H;poll_count<=0;end
                    else if(rx_ready && poll_count>=POLL_CYCLES-1)begin state<=SIZE_H;poll_count<=0;end
                    else if(poll_count<POLL_CYCLES)poll_count<=poll_count+1'b1;
                end
                SIZE_H:transaction(0,16'h0026,SREG,0,SIZE_L);
                SIZE_L:begin high_byte<=last_read;transaction(0,16'h0027,SREG,0,SIZE_H2);end
                SIZE_H2:begin available<={high_byte,last_read};transaction(0,16'h0026,SREG,0,SIZE_L2);end
                SIZE_L2:begin second_high<=last_read;transaction(0,16'h0027,SREG,0,RD_H);end
                RD_H:if({second_high,last_read}!=available)state<=SIZE_H;
                    else if(available<8)state<=IDLE;
                    else transaction(0,16'h0028,SREG,0,RD_L);
                RD_L:begin high_byte<=last_read;transaction(0,16'h0029,SREG,0,HEADER);hdr_index<=0;end
                HEADER:begin
                    if(hdr_index==0)rx_pointer<={high_byte,last_read};
                    transaction(0,({high_byte,last_read}+hdr_index)&16'h07ff,SRX,0,HEADER_NEXT);
                    // Preserve the pointer in a register after the first header byte.
                    if(hdr_index!=0)begin xfer_addr<=(rx_pointer+hdr_index)&16'h07ff;end
                end
                HEADER_NEXT:begin
                    if(hdr_index<6)rx_peer<={rx_peer[39:0],last_read};
                    else if(hdr_index==6)payload_length[15:8]<=last_read;
                    else payload_length[7:0]<=last_read;
                    if(hdr_index==7)state<=VALIDATE;
                    else begin hdr_index<=hdr_index+1'b1;state<=HEADER;end
                end
                VALIDATE:begin
                    offset<=0;
                    discard<=payload_length<20 || payload_length>1044;
                    if(payload_length>2040)begin next_pointer<=rx_pointer+available;state<=RD_SET_H;end
                    else if(available<8+payload_length)state<=IDLE;
                    else begin next_pointer<=rx_pointer+8+payload_length;state<=START;end
                end
                START:begin
                    if(discard)state<=RD_SET_H;
                    else if(rx_ready)begin rx_start<=1;state<=RXBYTE;end
                end
                RXBYTE:transaction(0,(rx_pointer+8+offset)&16'h07ff,SRX,0,RXNEXT);
                RXNEXT:begin
                    rx_data<=last_read;rx_valid<=1;
                    if(offset+1==payload_length)state<=RD_SET_H;
                    else begin offset<=offset+1'b1;state<=RXBYTE;end
                end
                RD_SET_H:transaction(1,16'h0028,SREG,next_pointer[15:8],RD_SET_L);
                RD_SET_L:transaction(1,16'h0029,SREG,next_pointer[7:0],RECV);
                RECV:begin
                    if(!discard)begin rx_end<=1;packets_received<=packets_received+1'b1;end
                    transaction(1,16'h0001,SREG,8'h40,RECV_DONE);
                end
                RECV_DONE:begin after_cr<=IDLE;state<=CR;end
                TX_FREE_H:transaction(0,16'h0020,SREG,0,TX_FREE_L);
                TX_FREE_L:begin high_byte<=last_read;transaction(0,16'h0021,SREG,0,TX_DEST);dest_index<=0;end
                TX_DEST:begin
                    if(dest_index==0 && {high_byte,last_read}<36)state<=TX_FREE_H;
                    else transaction(1,16'h000c+dest_index,SREG,destination[47:40],TX_DEST_NEXT);
                end
                TX_DEST_NEXT:begin
                    destination<={destination[39:0],8'd0};
                    if(dest_index==5)state<=TX_PTR_H;
                    else begin dest_index<=dest_index+1'b1;state<=TX_DEST;end
                end
                TX_PTR_H:transaction(0,16'h0024,SREG,0,TX_PTR_L);
                TX_PTR_L:begin high_byte<=last_read;transaction(0,16'h0025,SREG,0,TXBYTE);offset<=0;end
                TXBYTE:begin
                    if(offset==0)tx_pointer<={high_byte,last_read};
                    if(tx_valid)begin
                        transaction(1,((offset==0?{high_byte,last_read}:tx_pointer)+offset)&16'h07ff,STX,tx_data,TXNEXT);
                    end
                end
                TXNEXT:begin
                    tx_ready<=1;
                    if(offset==35)begin next_pointer<=tx_pointer+36;state<=TX_SET_H;end
                    else begin offset<=offset+1'b1;state<=TX_ADV;end
                end
                TX_ADV:state<=TXBYTE;
                // TX-ready is observed by the receiver one cycle later. WAIT_IO
                // request launch must not sample the same byte a second time.
                TX_SET_H:transaction(1,16'h0024,SREG,next_pointer[15:8],TX_SET_L);
                TX_SET_L:transaction(1,16'h0025,SREG,next_pointer[7:0],TX_SEND);
                TX_SEND:transaction(1,16'h0001,SREG,8'h20,TX_POLL);
                TX_POLL:transaction(0,16'h0002,SREG,0,TX_POLL_NEXT);
                TX_POLL_NEXT:begin
                    if(last_read[4] || last_read[3])begin
                        if(last_read[3])error<=1;
                        else packets_sent<=packets_sent+1'b1;
                        transaction(1,16'h0002,SREG,8'h18,IDLE);
                    end else state<=TX_POLL;
                end
                WAIT_IO:if(xfer_done)begin last_read<=xfer_rdata;state<=return_state;end
                default:state<=INIT;
            endcase
            if(timeout_count>=250000000)begin error<=1;cfg_index<=0;state<=INIT;end
        end
    end
endmodule
