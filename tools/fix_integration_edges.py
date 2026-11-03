from pathlib import Path
s=Path(__file__).resolve().parents[1]/'src/user_source/hdl_source'
p=s/'boot_video_stream.v';t=p.read_text(encoding='utf-8')
t=t.replace('reg [7:0] sf_dout;', 'reg [7:0] sf_read;\nreg sf_forward;\nreg [7:0] sf_forward_data;\nwire [7:0] sf_dout=sf_forward ? sf_forward_data : sf_read;')
t=t.replace('always @(posedge clk) sf_dout <= sfifo[sf_next_address];','''always @(posedge clk) begin
    sf_read <= sfifo[sf_next_address];
    sf_forward <= sd_sec_read_data_valid && state!=S_HDR && sf_wptr[9:0]==sf_next_address;
    sf_forward_data <= sd_sec_read_data;
end''')
t=t.replace("emit_ph   <= 2'd0;", "emit_ph   <= 2'd3;")
p.write_text(t,encoding='utf-8')
p=s/'network/hxfp_frame_bridge.v';t=p.read_text(encoding='utf-8')
t=t.replace('output wire write_owner,write_request,write_enable,','output wire write_owner,write_request,write_enable,\n output wire write_cancel,')
t=t.replace('assign write_request=state==REQUEST;','assign write_request=state==REQUEST;\n assign write_cancel=state==ABORTING;')
p.write_text(t,encoding='utf-8')
p=s/'top_tf_hdmi_audio.v';t=p.read_text(encoding='utf-8')
t=t.replace('wire image_write_owner,image_write_req,image_write_en,image_scheduler_hold;','wire image_write_owner,image_write_req,image_write_en,image_scheduler_hold;\nwire image_write_cancel;')
t=t.replace('.write_owner(image_write_owner),','.write_cancel(image_write_cancel),.write_owner(image_write_owner),')
t=t.replace('.write_top_down    (image_write_owner),','.write_top_down    (image_write_owner),\n    .write_cancel      (image_write_cancel),')
p.write_text(t,encoding='utf-8')
p=s/'SD/frame_read_write.v';t=p.read_text(encoding='utf-8')
t=t.replace('input                            write_top_down,','input                            write_top_down,\n    input                            write_cancel,')
t=t.replace('wire fifo_write_full;','''wire fifo_write_full;
(* async_reg="true" *) reg [1:0] write_cancel_sync;
always @(posedge mem_clk or posedge rst)
    if(rst)write_cancel_sync<=0;
    else write_cancel_sync<={write_cancel_sync[0],write_cancel};
wire write_reset=rst | write_cancel_sync[1];''')
t=t.replace('(write_fifo_aclr          )','(write_fifo_aclr | write_reset)')
pos=t.index('frame_fifo_write_m0')
a=t[:pos];b=t[pos:]
b=b.replace('(rst                      )','(write_reset              )',1)
p.write_text(a+b,encoding='utf-8')
p=s/'spectrum_fft_1024.v';t=p.read_text(encoding='utf-8')
a=t.index('wire [5:0] band_address');b=t.index('reg [63:0] divide_numerator',a)
block=t[a:b];t=t[:a]+t[b:];pos=t.index('integer clear_index;');t=t[:pos]+block+'\n'+t[pos:]
p.write_text(t,encoding='utf-8')
