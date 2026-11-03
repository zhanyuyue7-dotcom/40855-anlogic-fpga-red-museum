from pathlib import Path
r=Path(__file__).resolve().parents[1]
p=r/'src/user_source/hdl_source/SD/bmp_read.v'
t=(r/'baseline-src/user_source/hdl_source/SD/bmp_read.v').read_text(encoding='utf-8')
t=t.replace('wire header_match;','wire header_match;\nreg header_match_q;\nreg [31:0] next_match_q,next_miss_q;')
at=t.index('assign ready =')
block='''// Header bytes are stable before sector end; precompute scan decisions.
always @(posedge clk or posedge rst)begin
 if(rst)begin header_match_q<=0;next_match_q<=0;next_miss_q<=0;end
 else begin
  header_match_q<=header_match;
  next_match_q<=next_scan_sector_if_match;
  next_miss_q<=next_scan_sector_if_miss;
 end
end
'''
t=t[:at]+block+t[at:]
t=t.replace('if (header_match)','if (header_match_q)')
t=t.replace('<= next_scan_sector_if_match;','<= next_match_q;').replace('<= next_scan_sector_if_miss;','<= next_miss_q;')
t=t.replace('(next_scan_sector_if_match > scan_max_sector)','(next_match_q > scan_max_sector)')
p.write_text(t,encoding='utf-8')
p=r/'src/user_source/hdl_source/spectrum_sync_ram_1024.v'
t=p.read_text(encoding='utf-8')
t=t.replace('reg [DATA_WIDTH-1:0] mem [0:1023]; /* fehdl force_ram=1, ram_style="bram" */','(* ram_style="bram_32k" *) reg [DATA_WIDTH-1:0] mem [0:1023];')
p.write_text(t,encoding='utf-8')
