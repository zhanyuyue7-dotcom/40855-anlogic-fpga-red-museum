from pathlib import Path
r=Path(__file__).resolve().parents[1]
p=r/'src/user_source/hdl_source/network/hxfp_receiver.v'
t=p.read_text(encoding='utf-8')
t=t.replace('COMMIT_WAIT=5, TX_CRC=6, TX_SEND=7;', 'COMMIT_WAIT=5, TX_CRC=6, TX_SEND=7, WRITE_FETCH=8;')
t=t.replace('reg [7:0] payload [0:MAX_CHUNK-1];', '''reg [7:0] metadata [0:11];
    reg [15:0] pixel_memory [0:MAX_CHUNK/2-1]; /* fehdl force_ram=1, ram_style="bram" */
    reg [7:0] pixel_low;
    reg [15:0] pixel_word;
    always @(posedge clk) begin
        if (state==RX && collecting && rx_valid && rx_count>=20 && rx_count<20+MAX_CHUNK && rx_count[0])
            pixel_memory[(rx_count-20)>>1] <= {rx_data,pixel_low};
        pixel_word <= pixel_memory[write_pos>>1];
    end''')
import re
t=re.sub(r'payload\[(\d+)\]',r'metadata[\1]',t)
t=t.replace('crc_byte(crc_byte(image_crc,payload[write_pos]),payload[write_pos+1])', 'crc_byte(crc_byte(image_crc,pixel_word[7:0]),pixel_word[15:8])')
t=t.replace('{payload[write_pos+1],payload[write_pos]}', 'pixel_word')
t=t.replace('else payload[rx_count-20]<=rx_data;', '''else begin
                                if(rx_count<32) metadata[rx_count-20]<=rx_data;
                                if(!rx_count[0]) pixel_low<=rx_data;
                            end''')
t=t.replace('state<=WRITE; end', 'state<=WRITE_FETCH; end')
t=t.replace('''                WRITE: begin''','''                WRITE_FETCH: state<=WRITE;
                WRITE: begin''')
t=t.replace('else write_pos<=write_pos+2;', 'else begin write_pos<=write_pos+2;state<=WRITE_FETCH;end')
assert 'payload[' not in t
p.write_text(t,encoding='utf-8')
# Cosimulation uses precisely the same optimized module as production.
(r/'fpga_upload/rtl/hxfp_receiver.v').write_text(t,encoding='utf-8')
print('HXFP payload mapped to synchronous 16-bit packet RAM')
