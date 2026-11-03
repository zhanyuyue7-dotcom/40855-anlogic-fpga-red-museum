from pathlib import Path
import re
r=Path(__file__).resolve().parents[1]
s=r/'src/user_source/hdl_source'
p=s/'top_tf_hdmi_audio.v'
t=p.read_text(encoding='utf-8')
declarations='''
// HXFP register port is queued beside the legacy command client.
wire image_reg_start,image_reg_write,image_reg_done;
wire [15:0] image_reg_addr;
wire [4:0] image_reg_block;
wire [7:0] image_reg_wdata,image_reg_rdata;
wire merged_reg_start,merged_reg_write,merged_reg_done;
wire [15:0] merged_reg_addr;
wire [4:0] merged_reg_block;
wire [7:0] merged_reg_wdata,merged_reg_rdata;
wire image_rx_ready,image_rx_start,image_rx_valid,image_rx_end;
wire [7:0] image_rx_data;
wire [47:0] image_rx_peer,image_tx_peer;
wire image_tx_valid,image_tx_ready,image_tx_last;
wire [7:0] image_tx_data;
wire image_begin,image_begin_ready,image_commit,image_commit_ready,image_abort,image_fault;
wire image_pixel_valid,image_pixel_ready;
wire [15:0] image_pixel_rgb;
wire image_write_owner,image_write_req,image_write_en,image_scheduler_hold;
wire [31:0] image_write_data;
wire [1:0] image_write_index;
wire image_display_valid;
wire [1:0] image_display_index;
wire shared_write_ready;
wire image_network_error;
wire bmp_load_busy;
(* async_reg="true" *) reg [1:0] image_owner_pixel;
(* async_reg="true" *) reg [1:0] image_boot_sync,image_boot_sd_sync,image_mem_ready_sync;
(* async_reg="true" *) reg [1:0] image_bmp_busy_sync;
'''
t=t.replace('wire [23:0] vout_data_raw;',declarations+'\nwire [23:0] vout_data_raw;',1)
start=t.index('w5500_spi_arbiter u_w5500_spi_arbiter(')
end=t.index('\n);',start)+3
block=t[start:end]
for a,b in [('udp_start(w5500_udp_xfer_start)','udp_start(merged_reg_start)'),
            ('udp_write(w5500_udp_xfer_write)','udp_write(merged_reg_write)'),
            ('udp_addr(w5500_udp_xfer_addr)','udp_addr(merged_reg_addr)'),
            ('udp_block(w5500_udp_xfer_block)','udp_block(merged_reg_block)'),
            ('udp_wdata(w5500_udp_xfer_wdata)','udp_wdata(merged_reg_wdata)'),
            ('udp_done(w5500_udp_xfer_done)','udp_done(merged_reg_done)'),
            ('udp_rdata(w5500_udp_xfer_rdata)','udp_rdata(merged_reg_rdata)')]:
    assert a in block,a
    block=block.replace(a,b)
t=t[:start]+block+t[end:]
instances='''
w5500_reg_mux2 u_image_reg_mux(
 .clk(clk),.rst(rst_all),
 .a_start(w5500_udp_xfer_start),.a_write(w5500_udp_xfer_write),.a_addr(w5500_udp_xfer_addr),
 .a_block(w5500_udp_xfer_block),.a_wdata(w5500_udp_xfer_wdata),.a_done(w5500_udp_xfer_done),.a_rdata(w5500_udp_xfer_rdata),
 .b_start(image_reg_start),.b_write(image_reg_write),.b_addr(image_reg_addr),
 .b_block(image_reg_block),.b_wdata(image_reg_wdata),.b_done(image_reg_done),.b_rdata(image_reg_rdata),
 .out_start(merged_reg_start),.out_write(merged_reg_write),.out_addr(merged_reg_addr),
 .out_block(merged_reg_block),.out_wdata(merged_reg_wdata),.out_done(merged_reg_done),.out_rdata(merged_reg_rdata));
w5500_image_udp u_image_transport(
 .clk(clk),.rst(rst_all),.enable(w5500_init_done),
 .xfer_start(image_reg_start),.xfer_write(image_reg_write),.xfer_addr(image_reg_addr),
 .xfer_block(image_reg_block),.xfer_wdata(image_reg_wdata),.xfer_done(image_reg_done),.xfer_rdata(image_reg_rdata),
 .rx_ready(image_rx_ready),.rx_start(image_rx_start),.rx_valid(image_rx_valid),.rx_end(image_rx_end),
 .rx_data(image_rx_data),.rx_peer(image_rx_peer),
 .tx_valid(image_tx_valid),.tx_ready(image_tx_ready),.tx_last(image_tx_last),.tx_data(image_tx_data),.tx_peer(image_tx_peer),
 .packets_received(),.packets_sent(),.error(image_network_error));
hxfp_receiver u_image_receiver(
 .clk(clk),.rst(rst_all),.rx_ready(image_rx_ready),.rx_start(image_rx_start),.rx_valid(image_rx_valid),
 .rx_data(image_rx_data),.rx_end(image_rx_end),.rx_peer(image_rx_peer),
 .tx_valid(image_tx_valid),.tx_ready(image_tx_ready),.tx_data(image_tx_data),.tx_last(image_tx_last),.tx_peer(image_tx_peer),
 .frame_begin(image_begin),.frame_begin_ready(image_begin_ready),
 .pixel_valid(image_pixel_valid),.pixel_ready(image_pixel_ready),.pixel_address(),.pixel_rgb565(image_pixel_rgb),
 .frame_commit(image_commit),.frame_commit_ready(image_commit_ready),.frame_abort(image_abort),.frame_error(image_fault),
 .transfer_active(),.received_bytes(),.displayed_frames());
hxfp_frame_bridge u_image_bridge(
 .net_clk(clk),.sd_clk(sd_card_clk),.video_clk(video_clk),.rst(rst_all),
 .begin_request(image_begin),.begin_ready(image_begin_ready),.commit_request(image_commit),.commit_ready(image_commit_ready),
 .abort_request(image_abort),.pixel_valid(image_pixel_valid),.pixel_ready(image_pixel_ready),.pixel_rgb565(image_pixel_rgb),
 .storage_error(storage_fault_active),.frame_error(image_fault),
 .boot_active(image_boot_sync[1]),.boot_owns_sd(boot_sd_owner),.bmp_busy(bmp_load_busy),
 .transition_busy(transition_block_sd),.mem_ready(image_mem_ready_sync[1]),.hold_scheduler(image_scheduler_hold),
 .write_owner(image_write_owner),.write_request(image_write_req),.write_enable(image_write_en),
 .write_data(image_write_data),.write_index(image_write_index),
 .write_ack(sd_card_write_req_ack),.write_fifo_ready(shared_write_ready),.write_finish_toggle(frame_write_toggle_mem),
 .vs(vs),.de(de),.read_req_ack(video_read_req_ack),.tf_commit_toggle(display_commit_toggle),
 .display_valid(image_display_valid),.display_index(image_display_index),.displayed_count());
always @(posedge sd_card_clk or posedge rst_all)begin
 if(rst_all)begin image_boot_sync<=0;image_mem_ready_sync<=0;end
 else begin image_boot_sync<={image_boot_sync[0],boot_active_on};image_mem_ready_sync<={image_mem_ready_sync[0],Sdr_init_done};end
end
'''
t=t.replace('// Slideshow controls are independent',instances+'\n// Slideshow controls are independent',1)
t=t.replace('.transition_block  (transition_block_sd)', '.transition_block  (transition_block_sd | image_scheduler_hold)')
t=t.replace('.display_valid     (display_valid),', '.display_valid     (display_valid),\n    .load_busy         (bmp_load_busy),',1)
t=t.replace('.write_req_ack     (sd_card_write_req_ack),', '.write_req_ack     (sd_card_write_req_ack & ~image_write_owner),',1)
t=t.replace('assign sd_card_write_req  = boot_sd_owner ? boot_write_req  : bmp_write_req;', 'assign sd_card_write_req = image_write_owner ? image_write_req : (boot_sd_owner ? boot_write_req : bmp_write_req);')
t=t.replace('assign sd_card_write_en   = boot_sd_owner ? boot_write_en   : bmp_write_en;', 'assign sd_card_write_en = image_write_owner ? image_write_en : (boot_sd_owner ? boot_write_en : bmp_write_en);')
t=t.replace('assign sd_card_write_data = boot_sd_owner ? boot_write_data : bmp_write_data;', 'assign sd_card_write_data = image_write_owner ? image_write_data : (boot_sd_owner ? boot_write_data : bmp_write_data);')
t=t.replace('assign ffrw_write_index   = boot_sd_owner ? boot_write_index : write_buf_idx;', 'assign ffrw_write_index = image_write_owner ? image_write_index : (boot_sd_owner ? boot_write_index : write_buf_idx);')
t=t.replace('assign ffrw_read_index    = boot_active_on ? boot_read_index : disp_buf_idx_video;', 'assign ffrw_read_index = boot_active_on ? boot_read_index : (image_display_valid ? image_display_index : disp_buf_idx_video);')
t=t.replace('(boot_pixel_shown | pixel_sd_monitor[56])', '(boot_pixel_shown | pixel_sd_monitor[56] | image_display_valid)')
t=t.replace('.write_clk         (sd_card_clk),', '.write_clk         (sd_card_clk),\n    .write_top_down    (image_write_owner),\n    .write_ready       (shared_write_ready),',1)
p.write_text(t,encoding='utf-8')

p=s/'SD/frame_read_write.v';t=p.read_text(encoding='utf-8')
t=t.replace('input                            write_clk,','input                            write_top_down,\n    output wire                      write_ready,\n    input                            write_clk,',1)
t=t.replace('wire 							 App_rd_busy;', 'wire 							 App_rd_busy;')
t=t.replace('//instantiate an asynchronous FIFO \nwfifo_', 'wire fifo_write_full;\nassign write_ready = !fifo_write_full && !write_fifo_aclr;\n//instantiate an asynchronous FIFO \nwfifo_',1)
assert 'fifo_write_full' in t
t=t.replace('.full_flag                  (                         )', '.full_flag                  (fifo_write_full          )',1)
t=t.replace('.write_req                  (write_req                ),', '.write_req                  (write_req                ),\n    .write_top_down             (write_top_down),',1)
p.write_text(t,encoding='utf-8')
p=s/'SD/frame_fifo_write.v';t=p.read_text(encoding='utf-8')
t=t.replace('input                            write_req,','input                            write_top_down,\n    input                            write_req,',1)
t=t.replace('reg                                 write_req_d0;', '''(* async_reg="true" *) reg [1:0] top_down_sync;
reg flip_latched;
always @(posedge mem_clk or posedge rst)begin
 if(rst)begin top_down_sync<=0;flip_latched<=WRITE_V_FLIP;end
 else begin
  top_down_sync<={top_down_sync[0],write_top_down};
  if(state==S_IDLE || state==S_ACK)flip_latched<=WRITE_V_FLIP && !top_down_sync[1];
 end
end
reg                                 write_req_d0;''',1)
t=t.replace('WRITE_V_FLIP ?', 'flip_latched ?').replace('if(WRITE_V_FLIP)', 'if(flip_latched)')
p.write_text(t,encoding='utf-8')

# Requests must be captured even while an HTTP burst owns the physical SPI.
p=s/'network/w5500_spi_arbiter.v';t=p.read_text(encoding='utf-8')
position='''            if (burst_owner) begin'''
t=t.replace(position,'''            if(burst_owner && udp_start && !udp_pending)begin
                udp_pending<=1;udp_pending_write<=udp_write;udp_pending_addr<=udp_addr;
                udp_pending_block<=udp_block;udp_pending_wdata<=udp_wdata;
            end
            if(burst_owner && http_start && !http_pending)begin
                http_pending<=1;http_pending_write<=http_write;http_pending_addr<=http_addr;
                http_pending_block<=http_block;http_pending_wdata<=http_wdata;
            end
'''+position,1)
p.write_text(t,encoding='utf-8')

# TD XML contains historical unescaped ampersands; keep the existing format and
# add only local source entries and the relocated project directory.
p=r/'src/td_project/HDMI1.4b_Transmitter_v1.0.al';t=p.read_text(encoding='utf-8')
t=re.sub(r'(<Project[^>]* Path=")[^"]+',lambda m:m.group(1)+(r/'src/td_project').as_posix(),t,count=1)
nodes=''
for i,name in enumerate(('hxfp_receiver.v','hxfp_frame_bridge.v','w5500_image_udp.v','w5500_reg_mux2.v')):
 nodes+=f'''            <File Path="../user_source/hdl_source/network/{name}">
                <FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/>
                <Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="{490+i}"/></FileInfo>
            </File>\n'''
t=t.replace('        </Verilog>',nodes+'        </Verilog>',1)
p.write_text(t,encoding='utf-8')
print('Integrated HXFP transport, safe write ownership and frame commit into teammate top')
