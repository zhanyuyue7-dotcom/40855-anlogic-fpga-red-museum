// Reserve a non-visible boot bank after boot playback, stream through a real
// async FIFO, wait for memory write completion and finally a new visible frame.
// No ACK for COMMIT is produced from a FIFO-enqueue event.
module hxfp_frame_bridge #(
 parameter integer FRAME_PIXELS=307200
)(
 input wire net_clk,sd_clk,video_clk,rst,
 input wire begin_request,commit_request,abort_request,
 output wire begin_ready,commit_ready,
 input wire pixel_valid,input wire [15:0] pixel_rgb565,output wire pixel_ready,
 input wire storage_error,output wire frame_error,
 input wire boot_active,boot_owns_sd,bmp_busy,transition_busy,mem_ready,
 output wire hold_scheduler,
 output wire write_owner,write_request,write_enable,
 output wire write_cancel,
 output wire [31:0] write_data,output reg [1:0] write_index,
 input wire write_ack,write_fifo_ready,write_finish_toggle,
 input wire vs,de,read_req_ack,tf_commit_toggle,
 output reg display_valid,output reg [1:0] display_index,
 output reg [31:0] displayed_count
);
 localparam [3:0] IDLE=0,LOCK=1,REQUEST=2,RELEASE=3,STREAM=4,
     DRAIN=5,COMMIT=6,DONE=7,ABORTING=8;
 reg [3:0] state;
 reg [5:0] settle;
 (* async_reg="true" *) reg [1:0] begin_sd,commit_sd,ack_sd,finish_sd,error_sd;
 (* async_reg="true" *) reg [1:0] allocated_net,done_net,fault_net;
 reg abort_toggle;
 (* async_reg="true" *) reg [2:0] abort_sd;
 reg aborted_seen,finish_seen,write_complete,allocated,fault;
 reg commit_toggle;
 (* async_reg="true" *) reg [2:0] display_ack_sd;
 reg display_ack_seen;
 reg [18:0] sent_pixels;
 (* async_reg="true" *) reg [1:0] display_bank_sd;
 wire fifo_empty,fifo_full;
 wire [31:0] fifo_data;
 wire fifo_valid;
 reg fetch_pending,buffer_valid;
 reg [31:0] buffered_pixel;
 wire fifo_pop=state==STREAM && !fifo_empty && !fetch_pending && !buffer_valid;
 wire fifo_reset=rst || state==IDLE || state==LOCK || state==ABORTING;
 wire [31:0] expanded={pixel_rgb565[15:11],pixel_rgb565[15:13],
    pixel_rgb565[10:5],pixel_rgb565[10:9],pixel_rgb565[4:0],pixel_rgb565[4:2],8'd0};
 assign begin_ready=allocated_net[1];
 assign commit_ready=done_net[1];
 assign frame_error=fault_net[1];
 assign pixel_ready=begin_ready && !fifo_full && !fault_net[1];
 assign hold_scheduler=state!=IDLE || begin_sd[1];
 assign write_owner=state!=IDLE && state!=LOCK;
 assign write_request=state==REQUEST;
 assign write_cancel=state==ABORTING;
 // Registered delivery breaks the FIFO pointer/empty -> shared writer path.
 // A read is issued only with an empty holding register; backpressure cannot
 // lose a pixel. The SPI ingress is far slower than this four-cycle service.
 assign write_enable=state==STREAM && buffer_valid && write_fifo_ready;
 assign write_data=buffered_pixel;
 always @(posedge sd_clk or posedge rst)begin
  if(rst)begin fetch_pending<=0;buffer_valid<=0;buffered_pixel<=0;end
  else if(fifo_reset)begin fetch_pending<=0;buffer_valid<=0;end
  else begin
   if(fifo_pop)fetch_pending<=1;
   if(fifo_valid && fetch_pending)begin
    buffered_pixel<=fifo_data;buffer_valid<=1;fetch_pending<=0;
   end
   if(write_enable)buffer_valid<=0;
  end
 end
 wfifo_32_32_512 #(.SHOW_AHEAD_EN(1'b0)) u_pixels(
   .rst(fifo_reset),.clkw(net_clk),.clkr(sd_clk),
   .we(pixel_valid && pixel_ready),.di(expanded),.re(fifo_pop),
   .dout(fifo_data),.empty_flag(fifo_empty),.full_flag(fifo_full),
   .wrusedw(),.rdusedw(),.valid(fifo_valid),.afull(),.aempty());
 always @(posedge net_clk or posedge rst)begin
  if(rst)begin allocated_net<=0;done_net<=0;fault_net<=0;abort_toggle<=0;end
  else begin
   allocated_net<={allocated_net[0],allocated};
   done_net<={done_net[0],state==DONE};
   fault_net<={fault_net[0],fault};
   if(abort_request)abort_toggle<=~abort_toggle;
  end
 end
 reg display_ack;
 always @(posedge sd_clk or posedge rst)begin
  if(rst)begin
   state<=IDLE;settle<=0;begin_sd<=0;commit_sd<=0;ack_sd<=0;finish_sd<=0;error_sd<=0;
   abort_sd<=0;aborted_seen<=0;finish_seen<=0;write_complete<=0;allocated<=0;fault<=0;
   write_index<=2;sent_pixels<=0;commit_toggle<=0;display_ack_sd<=0;display_ack_seen<=0;
  end else begin
   begin_sd<={begin_sd[0],begin_request};commit_sd<={commit_sd[0],commit_request};
   ack_sd<={ack_sd[0],write_ack};finish_sd<={finish_sd[0],write_finish_toggle};
   error_sd<={error_sd[0],storage_error};abort_sd<={abort_sd[1:0],abort_toggle};
   display_ack_sd<={display_ack_sd[1:0],display_ack};
   case(state)
    IDLE:begin
     allocated<=0;fault<=0;write_complete<=0;settle<=0;
     finish_seen<=finish_sd[1];display_ack_seen<=display_ack_sd[2];
     if(begin_sd[1] && !boot_active && !boot_owns_sd)state<=LOCK;
    end
    LOCK:begin
     // Lock scheduling first, then allow already-started producers to retire.
     if(bmp_busy || transition_busy || !mem_ready || ack_sd[1])settle<=0;
     else if(settle==31)begin
      write_index<=display_bank_sd[1] ? 2'd2 : 2'd3;
      state<=REQUEST;settle<=0;finish_seen<=finish_sd[1];
     end else settle<=settle+1'b1;
    end
    REQUEST:if(ack_sd[1])begin state<=RELEASE;settle<=0;end
    RELEASE:if(!ack_sd[1])begin
     if(settle==15)begin allocated<=1;sent_pixels<=0;state<=STREAM;end
     else settle<=settle+1'b1;
    end
    STREAM:begin
     if(write_enable)begin
      sent_pixels<=sent_pixels+1'b1;
      if(sent_pixels==FRAME_PIXELS-1)state<=DRAIN;
     end
    end
    DRAIN:if(write_complete && commit_sd[1])begin
     commit_toggle<=~commit_toggle;state<=COMMIT;
    end
    COMMIT:if(display_ack_sd[2]!=display_ack_seen)begin
     display_ack_seen<=display_ack_sd[2];state<=DONE;allocated<=0;
    end
    DONE:if(!commit_sd[1])state<=IDLE;
    ABORTING:begin
     // A fresh write-request handshake on the next BEGIN resets the abandoned
     // writer/FIFO. The partial offscreen bank is never made visible.
     allocated<=0;
     if(!begin_sd[1] && !commit_sd[1])state<=IDLE;
    end
    default:state<=IDLE;
   endcase
   if(finish_sd[1]!=finish_seen)begin
    finish_seen<=finish_sd[1];
    if(state==STREAM || state==DRAIN)write_complete<=1;
   end
   if(abort_sd[2]!=aborted_seen)begin
    aborted_seen<=abort_sd[2];
    if(state!=COMMIT && state!=DONE && state!=IDLE)state<=ABORTING;
   end
   if(error_sd[1] && state!=IDLE && state!=LOCK)begin fault<=1;allocated<=0;state<=ABORTING;end
  end
 end
 always @(posedge sd_clk or posedge rst)
  if(rst)display_bank_sd<=0;
  else display_bank_sd<={display_bank_sd[0],display_index[0]};

 (* async_reg="true" *) reg [2:0] commit_video,tf_commit_video;
 (* async_reg="true" *) reg [1:0] bank_meta,bank_video,read_ack_video;
 reg commit_seen,tf_seen,vs_prev,ack_prev;
 reg [1:0] phase;
 wire frame_boundary=vs_prev && !vs && !de;
 always @(posedge video_clk or posedge rst)begin
  if(rst)begin
   commit_video<=0;tf_commit_video<=0;bank_meta<=2;bank_video<=2;
   read_ack_video<=0;commit_seen<=0;tf_seen<=0;vs_prev<=0;ack_prev<=0;
   phase<=0;display_valid<=0;display_index<=2;display_ack<=0;displayed_count<=0;
  end else begin
   commit_video<={commit_video[1:0],commit_toggle};
   tf_commit_video<={tf_commit_video[1:0],tf_commit_toggle};
   bank_meta<=write_index;bank_video<=bank_meta;
   read_ack_video<={read_ack_video[0],read_req_ack};
   vs_prev<=vs;ack_prev<=read_ack_video[1];
   if(tf_commit_video[2]!=tf_seen)begin tf_seen<=tf_commit_video[2];display_valid<=0;end
   if(commit_video[2]!=commit_seen)begin commit_seen<=commit_video[2];phase<=1;end
   if(phase==1 && frame_boundary)begin
    display_index<=bank_video;display_valid<=1;phase<=2;
   end else if(phase==2 && frame_boundary)phase<=3;
   // A frame request with a stable new bank and a subsequent ACK is necessary.
   if(phase==3 && read_ack_video[1] && !ack_prev)begin
    display_ack<=~display_ack;displayed_count<=displayed_count+1'b1;phase<=0;
   end
  end
 end
endmodule
