from pathlib import Path
import re
s=Path(__file__).resolve().parents[1]/'src/user_source/hdl_source'
p=s/'osd_glyph_rom.v';t=p.read_text(encoding='utf-8')
entries=re.findall(r"10'd(\d+): row_bits <= 16'h([0-9a-fA-F]+);",t)
t='''// Same legacy glyph bitmap, stored in synchronous block ROM.
module osd_glyph_rom(input wire clk,input wire[5:0] glyph_id,input wire[3:0] row,output reg[15:0] row_bits);
(* rom_style="bram" *) reg[15:0] mem[0:1023];
integer i;
initial begin
 for(i=0;i<1024;i=i+1)mem[i]=0;
'''+''.join(f" mem[{i}]=16'h{value};\n" for i,value in entries)+'''end
always @(posedge clk)row_bits<=mem[{glyph_id,row}];
endmodule
'''
p.write_text(t,encoding='utf-8')
for name in ('spectrum_hann_rom.v','spectrum_twiddle_rom.v'):
 p=s/name;t=p.read_text(encoding='utf-8')
 t=t.replace('(input wire', '(input wire clk, input wire',1)
 t=re.sub(r'(reg signed \[15:0\] \w+ \[0:\d+\];)',r'(* rom_style="bram" *) \1',t)
 t=t.replace('always @*','always @(posedge clk)')
 p.write_text(t,encoding='utf-8')
p=s/'spectrum_fft_1024.v';t=p.read_text(encoding='utf-8')
t=t.replace('u_hann(.addr(', 'u_hann(.clk(clk),.addr(').replace('.addr(twiddle_addr),','.clk(clk),.addr(twiddle_addr),')
p.write_text(t,encoding='utf-8')
print('Legacy glyph and FFT coefficient ROMs use block memory; numerical contents unchanged')
