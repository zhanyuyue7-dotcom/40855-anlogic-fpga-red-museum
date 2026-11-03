from pathlib import Path
import re
s=Path(__file__).resolve().parents[1]/'src/user_source/hdl_source'
for name,width,rows,mult in [('osd_glyph_rom_24.v',24,1392,24),('osd_glyph_rom_20.v',20,1160,20)]:
    p=s/name;t=p.read_text(encoding='utf-8')
    t=re.sub(r'reg \[\d+:0\] mem \[0:\d+\];[^\n]*',f'(* rom_style="bram" *) reg [{width-1}:0] mem [0:2047];',t,count=1)
    t=t.replace('initial begin','initial begin\n        for(i=0;i<2048;i=i+1) mem[i]=0;',1)
    t=t.replace(f'row_bits <= mem[glyph_id*{mult} + row];',f'row_bits <= mem[row_address];')
    pos=t.index('    always @(posedge clk)')
    t=t[:pos]+f'    wire [10:0] row_address=glyph_id*{mult}+row;\n'+t[pos:]
    p.write_text(t,encoding='utf-8')
print('Applied documented rom_style before glyph array declarations')
