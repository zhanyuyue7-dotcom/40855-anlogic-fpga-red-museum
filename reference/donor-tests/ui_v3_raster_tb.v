`timescale 1ns/1ps
module ui_v3_raster_tb;
 reg clk=0,rst=1,hs=0,vs=1,de=0;
 reg [23:0] rgb=0;
 reg [1:0] scene=0,brightness=3;
 reg [3:0] state=0;
 reg adjust=0;
 wire oh,ov,od,lh,lv,ld,av,au,al;
 wire [23:0] out_rgb,legacy_rgb,axis_rgb;
 reg [23:0] golden[0:307199];
 reg [23:0] previous=0;
 reg pd=0,ph=0,pv=0,pu=0,pl=0;
 integer x,y,n,checks=0,sof=0,eol=0,errors=0,frame_errors=0,limit=0;
 string base,filename;
 subtitle_osd dut(clk,rst,hs,vs,de,rgb,scene,state,brightness,adjust,oh,ov,od,out_rgb,6'd32);
 subtitle_osd_baseline legacy(clk,rst,hs,vs,de,rgb,scene,state,brightness,adjust,lh,lv,ld,legacy_rgb);
 video_rgb_to_axis_640x480 axis(clk,rst,ov,od,out_rgb,au,av,al,axis_rgb);
 always #5 clk=~clk;
 task tick;
 input v,h,d;
 input [23:0] b;
 input integer index;
 input alert;
 reg [23:0] expected;
 begin
   @(negedge clk);vs=v;hs=h;de=d;rgb=b; #1;
   if({oh,ov,od,out_rgb} !== {ph,pv,pd,previous}) $fatal(1,"Output changed before registered edge");
   @(posedge clk);#1;
   expected=!d ? 24'd0 : alert ? legacy_rgb : golden[index];
   if({oh,ov,od} !== {h,v,d}) $fatal(1,"OSD control alignment");
   if(out_rgb !== expected) begin
     if(frame_errors<4) $display("MISMATCH frame=%0d xy=%0d,%0d rgb=%h expected=%h",n,x,y,out_rgb,expected);
     frame_errors=frame_errors+1; errors=errors+1;
   end
   if({av,au,al,axis_rgb} !== {pd,pu,pl,previous}) $fatal(1,"AXIS one-stage alignment");
   if(au) sof=sof+1;if(al)eol=eol+1;
   ph=h;pv=v;pd=d;previous=out_rgb;pu=d && index==0;pl=d && index%640==639;
   if(d) checks=checks+1;
 end endtask
 task blank;
 input v;
 integer i;
 begin for(i=0;i<8;i=i+1) tick(v,i[0],0,24'habcdef,0,0);end
 endtask
 task frame;
 input integer sc,st,br,mode;
 begin
   frame_errors=0;
   blank(1);tick(0,0,0,0,0,0);
   scene=sc;state=st;brightness=br;adjust=mode;blank(0);
   if(sc==0) begin filename=$sformatf("%s/expected-%0d.hex",base,n);$readmemh(filename,golden);end
   for(y=0;y<480;y=y+1) begin
     for(x=0;x<640;x=x+1) begin
       tick(0,x[2],1,{y[7:0],x[7:0],8'h5a},y*640+x,sc!=0);
       if(y==100 && x==200) begin scene=sc==0 ? 2 : 0;state=15-st;brightness=3-br;adjust=!mode;end
     end
     blank(0);
   end
   blank(0);
   $display("FRAME %0d scene=%0d state=%0d brightness=%0d mode=%0d mismatches=%0d",n,sc,st,br,mode,frame_errors);
 end endtask
 initial begin
   if(!$value$plusargs("base=%s",base))$fatal(1,"Missing reference directory");
   if($value$plusargs("limit=%d",limit)) begin end
   repeat(3)@(negedge clk);rst=0;
   @(posedge clk);#1;ph=oh;pv=ov;pd=od;previous=out_rgb;
   n=0;frame(0,0,0,0);
   if(limit==1) begin if(errors)$fatal(1,"RED frame mismatches=%0d",errors);$finish;end
   n=1;frame(0,1,1,1);n=2;frame(0,2,2,0);n=3;frame(0,3,3,1);
   n=4;frame(0,4,0,0);n=5;frame(0,15,3,1);n=6;frame(1,4,2,1);n=7;frame(2,2,1,0);n=8;frame(0,4,2,1);
   blank(0);
   if(errors || checks!=2764800 || sof!=9 || eol!=4320)$fatal(1,"pixels=%0d errors=%0d SOF=%0d EOL=%0d",checks,errors,sof,eol);
   @(negedge clk);rst=1;#1;if(od!==0 || out_rgb!==0)$fatal(1,"Reset leaked pixels");
   $display("PASS: 9 full frames / 2764800 pixels; 6 states, 4 brightness lengths, 2 modes, gold slogan, native glyph pixels, legacy equality, mid-frame freeze, return, reset, 9 SOF/4320 EOL");$finish;
 end
 initial begin #40000000;$fatal(1,"Raster watchdog");end
endmodule
