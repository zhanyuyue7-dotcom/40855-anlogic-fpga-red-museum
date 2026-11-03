"""Make large memories use synchronous BRAM; preserve the FFT arithmetic."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
src=root/'src/user_source/hdl_source'

for name in ('osd_glyph_rom_24.v','osd_glyph_rom_20.v'):
    p=src/name
    t=p.read_text(encoding='utf-8')
    import re
    t=re.sub(r'(reg \[\d+:0\] mem \[0:\d+\];)',r'\1 /* fehdl force_ram=1, ram_style="bram" */',t)
    p.write_text(t,encoding='utf-8')

p=src/'spectrum_fft_1024.v'
t=p.read_text(encoding='utf-8')
t=t.replace("ST_DIVIDE      = 4'd10;", "ST_DIVIDE      = 4'd10;\nlocalparam [3:0] ST_CLEAR_BANDS=4'd11, ST_FETCH_HEIGHT=4'd12;")
t=t.replace('reg signed [63:0] band_power [0:63];', '''reg signed [63:0] band_power [0:63]; /* fehdl force_ram=1, ram_style="bram" */
reg signed [63:0] band_read;
reg [5:0] clear_address;
reg max_phase;
wire [5:0] band_address = (state==ST_CLEAR_BANDS) ? clear_address :
    ((state==ST_SCAN_LEFT || state==ST_SCAN_RIGHT) ? scan_band_index[5:0] :
     ((state==ST_FIND_MAX) ? max_index : height_index));
always @(posedge clk) begin
    band_read <= band_power[band_address];
    if (state==ST_CLEAR_BANDS) band_power[clear_address] <= 0;
    else if ((state==ST_SCAN_LEFT || state==ST_SCAN_RIGHT) && scan_phase)
        band_power[scan_band_index] <= band_read + scan_power;
end''')
t=t.replace('$unsigned(band_power[height_index])','$unsigned(band_read)')
t=t.replace('''        for (clear_index=0; clear_index<64; clear_index=clear_index+1)
            band_power[clear_index] <= 64'd0;''','''        clear_address <= 0;
        max_phase <= 0;''')
t=t.replace('''                        for (clear_index=0; clear_index<64; clear_index=clear_index+1)
                            band_power[clear_index] <= 64'd0;
                        state <= ST_FFT_LEFT;''','''                        clear_address <= 0;
                        state <= ST_CLEAR_BANDS;''')
t=t.replace('''                    band_power[scan_band_index] <= band_power[scan_band_index] + scan_power;
''','')
t=t.replace('''            ST_FIND_MAX: begin
                if (band_power[max_index] > max_power)
                    max_power <= band_power[max_index];
                if (max_index == 6'd63) begin
                    height_index <= 6'd0;
                    state <= ST_START_HEIGHT;
                end else begin
                    max_index <= max_index + 6'd1;
                end
            end''','''            ST_CLEAR_BANDS: begin
                if (clear_address==63) state<=ST_FFT_LEFT;
                else clear_address<=clear_address+1'b1;
            end
            ST_FETCH_HEIGHT: state<=ST_START_HEIGHT;
            ST_FIND_MAX: begin
                max_phase <= ~max_phase;
                if (max_phase) begin
                    if (band_read > max_power) max_power <= band_read;
                    if (max_index == 6'd63) begin
                        height_index <= 6'd0;
                        state <= ST_FETCH_HEIGHT;
                    end else max_index <= max_index + 6'd1;
                end
            end''')
t=t.replace('state <= ST_START_HEIGHT;', 'state <= ST_FETCH_HEIGHT;')
assert 'band_power[clear_index]' not in t
p.write_text(t,encoding='utf-8')

# Boot byte FIFO uses synchronous prefetch at the *next* read address. This
# preserves the original first-word-fall-through interface without a LUT mux.
p=src/'boot_video_stream.v'
t=p.read_text(encoding='utf-8')
t=t.replace('reg  [7:0]  sfifo [0:1023];','reg  [7:0]  sfifo [0:1023]; /* fehdl force_ram=1, ram_style="bram" */')
t=t.replace('wire [7:0]  sf_dout  = sfifo[sf_rptr[9:0]];', '''reg [7:0] sf_dout;
wire sf_pop = state==S_DATA && row_state==R_RECV && sf_have && stall_cnt<STALL_TIMEOUT;
wire [9:0] sf_next_address = sf_rptr[9:0] + sf_pop;
always @(posedge clk) sf_dout <= sfifo[sf_next_address];''')
# Separate RAM write from asynchronous-reset pointer logic for valid inference.
t=t.replace('''            sfifo[sf_wptr[9:0]] <= sd_sec_read_data;
''','')
marker='always @(posedge clk or posedge rst) begin\n    if (rst) begin\n        sf_wptr'
t=t.replace(marker,'''always @(posedge clk) begin
    if (sd_sec_read_data_valid && state!=S_HDR) sfifo[sf_wptr[9:0]] <= sd_sec_read_data;
end
always @(posedge clk or posedge rst) begin
    if (rst) begin
        sf_wptr''')
# Read-address prefetch is kept stable for a full beat before px_hold capture.
t=t.replace('reg  [15:0] linebuf [0:SRC_W-1];','reg [15:0] linebuf [0:511]; /* fehdl force_ram=1, ram_style="bram" */\nreg [15:0] line_read;')
t=t.replace('''                            linebuf[px_x[8:0]] <= {sf_dout, byte_low};
''','')
t=t.replace('px_hold <= linebuf[px_x[8:0]];', 'px_hold <= line_read;')
# Combinational emit is removed: phase 3 explicitly prefetches a new pixel.
t=t.replace("emit_ph    <= 2'd0;\n                        px_x", "emit_ph    <= 2'd3;\n                        px_x")
t=t.replace('''                    case (emit_ph)
                    2'd0:''','''                    case (emit_ph)
                    2'd3: emit_ph <= 2'd0;
                    2'd0:''')
marker='// ------------------------------------------------------------------ handshake'
t=t.replace(marker,'''always @(posedge clk) begin
    line_read <= linebuf[px_x[8:0]];
    if (sf_pop && byte_phase) linebuf[px_x[8:0]] <= {sf_dout, byte_low};
end

'''+marker)
p.write_text(t,encoding='utf-8')
print('Updated synchronous band-power, boot buffers and glyph ROM hints')
