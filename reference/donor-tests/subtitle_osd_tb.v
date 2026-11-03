`timescale 1ns/1ps
module subtitle_osd_tb;
    reg clk=0, rst=1, hs=0, vs=0, de=0;
    reg [23:0] rgb=0;
    reg [1:0] scene=0;
    reg [3:0] state=0;
    reg [1:0] brightness=3;
    reg adjust=0;
    wire ohs, ovs, ode, av, au, al;
    wire [23:0] orgb, argb;
    reg [15:0] golden [0:1023];
    reg [1023:0] font_path;
    reg ph=0, pv=0, pd=0, pu=0, pl=0;
    reg [23:0] pc=0;
    integer x, y, frame_n, pixels=0, whites=0, sof=0, eol=0;
    subtitle_osd dut(.clk(clk),.rst(rst),.hs(hs),.vs(vs),.de(de),.rgb(rgb),
        .scene_id(scene),.run_state(state),.brightness_level(brightness),
        .adjust_mode(adjust),.ui_fade_level(6'd32),.hs_out(ohs),.vs_out(ovs),.de_out(ode),.rgb_out(orgb));
    video_rgb_to_axis_640x480 axis(clk,rst,ovs,ode,orgb,au,av,al,argb);
    always #5 clk=~clk;

    // Independent pixel reference driven by raster coordinates and glyph data.
    function [23:0] expected_pixel;
        input integer px, py, sc, st, br, mode;
        input [23:0] background;
        integer glyph, column, row, text_origin;
        reg panel, border, in_text, parameter_text;
        reg [15:0] bits;
        reg [23:0] accent;
        begin
            panel=(px>=16 && px<=623 && ((py>=16 && py<=71)||(py>=408 && py<=463)));
            border=panel && (py==16 || py==17 || py==70 || py==71 ||
                            py==408 || py==409 || py==462 || py==463);
            in_text=0; parameter_text=0; glyph=0; row=0; text_origin=32;
            column=(px-text_origin)/32;
            if (px>=32 && px<=383 && py>=28 && py<=59) begin
                in_text=1; row=(py-28)/2;
                case(column)
                    0:glyph=1; 1:glyph=2;
                    3:glyph=sc==0 ? 3 : sc==1 ? 7 : 9;
                    4:glyph=sc==0 ? 4 : sc==1 ? 8 : 10;
                    5:glyph=sc==0 ? 5 : 0; 6:glyph=sc==0 ? 6 : 0;
                    8:glyph=11; 9:glyph=12; 10:glyph=13+sc;
                    default:glyph=0;
                endcase
            end else if (px>=32 && px<=191 && py>=420 && py<=451) begin
                in_text=1; row=(py-420)/2;
                case(column)
                    0:glyph=18; 1:glyph=19;
                    3:case(st) 0,3:glyph=11; 1:glyph=21; 2:glyph=23; 4:glyph=25; default:glyph=27; endcase
                    4:case(st) 0,3:glyph=20; 1:glyph=22; 2:glyph=24; 4:glyph=26; default:glyph=28; endcase
                    default:glyph=0;
                endcase
            end else if (px>=224 && px<=607 && py>=420 && py<=451) begin
                in_text=1; parameter_text=1; row=(py-420)/2;
                text_origin=224; column=(px-text_origin)/32;
                case(column)
                    0:glyph=29; 1:glyph=30; // 亮度
                    3:case(br) 0:glyph=15; 1:glyph=31; 2:glyph=32; default:glyph=14; endcase
                    4:case(br) 0,2:glyph=31; 1:glyph=13; default:glyph=13; endcase
                    5:glyph=br==3 ? 13 : 33;
                    6:glyph=br==3 ? 33 : 0;
                    8:glyph=mode ? 34 : 18;
                    9:glyph=mode ? 35 : 19;
                    default:glyph=0;
                endcase
            end
            bits=golden[glyph*16+row];
            accent=sc==0 ? 24'h45b8ac : sc==1 ? 24'he0a020 : 24'hc82020;
            if(in_text && bits[15-((px-text_origin)%32)/2]) expected_pixel=24'hffffff;
            else if(border) expected_pixel=accent;
            else if(panel) expected_pixel=24'h101820;
            else expected_pixel=background;
        end
    endfunction
    task tick;
        input v,h,d;
        input [23:0] background, expected;
        input expected_user, expected_last;
        begin
            @(negedge clk); vs=v; hs=h; de=d; rgb=background; #1;
            if (ovs!==pv || ohs!==ph || ode!==pd || orgb!==pc)
                $fatal(1,"OSD bypassed its one-cycle stage");
            @(posedge clk); #1;
            if (ovs!==v || ohs!==h || ode!==d || orgb!==expected)
                $fatal(1,"OSD pixel/control mismatch frame=%0d x=%0d y=%0d rgb=%h expected=%h",frame_n,x,y,orgb,expected);
            if (av!==pd || au!==pu || al!==pl || argb!==pc)
                $fatal(1,"OSD to AXIS alignment mismatch at %0d,%0d",x,y);
            if(au) sof=sof+1; if(al) eol=eol+1;
            pv=v; ph=h; pd=d; pc=expected; pu=expected_user; pl=expected_last;
        end
    endtask
    task blank;
        input v;
        integer i;
        begin
            for(i=0;i<8;i=i+1) tick(v,i[0],0,24'habcdef,0,0,0);
        end
    endtask
    task frame;
        input [1:0] sc;
        input [3:0] st;
        input [1:0] br;
        input mode;
        reg [23:0] background, expected;
        begin
            brightness=br; adjust=mode; blank(1);
            tick(0,0,0,0,0,0,0);
            // Model M3 scene commit after the VS boundary edge.
            scene=sc; state=st;
            blank(0);
            for(y=0;y<480;y=y+1) begin
                for(x=0;x<640;x=x+1) begin
                    background={y[7:0],x[7:0],8'h5a};
                    expected=expected_pixel(x,y,sc,st,br,mode,background);
                    tick(0,x[2],1,background,expected,y==0 && x==0,x==639);
                    pixels=pixels+1; if(expected==24'hffffff) whites=whites+1;
                    if(y==100 && x==200) begin scene=2; state=4; brightness=0; adjust=~mode; end
                end
                blank(0);
            end
        end
    endtask
    initial begin
        if(!$value$plusargs("font_hex=%s",font_path)) $fatal(1,"Missing reference glyph data");
        $readmemh(font_path,golden);
        repeat(3) @(negedge clk); rst=0;
        frame_n=0; frame(0,1,3,0);
        frame_n=1; frame(1,4,2,1);
        frame_n=2; frame(2,2,1,0);
        frame_n=3; frame(0,15,0,1);
        blank(0);
        if(pixels!=1228800 || sof!=4 || eol!=1920 || whites<1000)
            $fatal(1,"Insufficient pixel, glyph or frame coverage");
        @(negedge clk); rst=1; #1;
        if(ode!==0 || orgb!==0) $fatal(1,"Reset left visible subtitle pixels");
        $display("PASS: OSD four full frames; scene/state, 25/50/75/100 percent, adjust/run mode, Chinese masks, alignment and frame-latched metadata");
        $finish;
    end
    initial begin #30000000; $fatal(1,"OSD timeout"); end
endmodule
