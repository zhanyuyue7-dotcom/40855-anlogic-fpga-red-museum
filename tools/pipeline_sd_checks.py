from pathlib import Path
s=Path(__file__).resolve().parents[1]/'src/user_source/hdl_source'
p=s/'audio_pcm_raw_reader.v';t=p.read_text(encoding='utf-8')
t=t.replace('reg [31:0] song_remaining;','reg [31:0] song_remaining;\nreg song_empty;')
t=t.replace("song_remaining    <= 32'd0;", "song_remaining    <= 32'd0;\n        song_empty <= 1;")
for n in range(3):
 import re
 t=re.sub(r'(song_remaining\s*<= entry'+str(n)+r'_len;)',r'\1\n                        song_empty <= entry'+str(n)+r'_len==0;',t)
t=t.replace('song_remaining == 0','song_empty').replace('song_remaining != 0','!song_empty')
t=t.replace("song_remaining <= song_remaining - 32'd1;", "song_remaining <= song_remaining - 32'd1;\n                            song_empty <= song_remaining==1;")
p.write_text(t,encoding='utf-8')
p=s/'SD/bmp_read.v';t=p.read_text(encoding='utf-8')
t=t.replace('wire header_match;', 'wire header_match;\nreg header_match_q;\nreg [31:0] next_match_q,next_miss_q;')
pos=t.index('always @(posedge clk or posedge rst)')
t=t[:pos]+'''// Header fields settle hundreds of byte clocks before sector end.
// Register comparisons/next addresses before they fan out to the scan FSM.
always @(posedge clk or posedge rst)begin
 if(rst)begin header_match_q<=0;next_match_q<=0;next_miss_q<=0;end
 else begin
  header_match_q<=header_match;
  next_match_q<=next_scan_sector_if_match;
  next_miss_q<=next_scan_sector_if_miss;
 end
end
'''+t[pos:]
t=t.replace('if (header_match)', 'if (header_match_q)')
for line in ('sd_sec_read_addr <= next_scan_sector_if_match;', 'scan_sector      <= next_scan_sector_if_match;',
             'sd_sec_read_addr <= next_scan_sector_if_miss;', 'scan_sector      <= next_scan_sector_if_miss;'):
 t=t.replace(line,line.replace('next_scan_sector_if_match','next_match_q').replace('next_scan_sector_if_miss','next_miss_q'))
t=t.replace('(next_scan_sector_if_match > scan_max_sector)', '(next_match_q > scan_max_sector)')
p.write_text(t,encoding='utf-8')
# Exact first-stage exception for the existing boot producer-consumer toggles.
# Second-stage and SDRAM paths remain timed, as in the upstream CDC contract.
p=s.parent/'constraints_source/timing.sdc';t=p.read_text(encoding='utf-8')
t+='\n# Reviewed boot buffer-release two-stage CDC: cons_s0 -> cons_s1.\n'
t+='set_false_path -hold -to [get_regs {u_boot_video_stream/cons_s0[0]}]\n'
t+='set_false_path -hold -to [get_regs {u_boot_video_stream/cons_s0[1]}]\n'
p.write_text(t,encoding='utf-8')
print('Registered SD header and song-empty conditions; exact boot CDC first-stage hold exceptions')
