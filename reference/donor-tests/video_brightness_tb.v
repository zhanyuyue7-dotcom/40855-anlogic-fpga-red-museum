`timescale 1ns/1ps
module video_brightness_tb;
    reg clk=0, rst=1, hs=0, vs=0, de=0;
    reg [23:0] rgb=0;
    reg [1:0] brightness_level=3;
    wire hs_out, vs_out, de_out;
    wire [23:0] rgb_out;

    video_brightness dut(
        .clk(clk),.rst(rst),.hs(hs),.vs(vs),.de(de),.rgb(rgb),
        .brightness_level(brightness_level),.hs_out(hs_out),
        .vs_out(vs_out),.de_out(de_out),.rgb_out(rgb_out)
    );
    always #5 clk=~clk;

    task sample;
        input v,h,d;
        input [23:0] color, expected;
        begin
            @(negedge clk);vs=v;hs=h;de=d;rgb=color;
            @(posedge clk);#1;
            if(vs_out!==v || hs_out!==h || de_out!==d || rgb_out!==expected)
                $fatal(1,"brightness/control mismatch level=%0d rgb=%h expected=%h",dut.frame_level,rgb_out,expected);
        end
    endtask
    task boundary;
        input [1:0] level;
        begin
            brightness_level=level;
            sample(1,0,0,24'hffffff,24'h000000);
            sample(0,1,0,24'hffffff,24'h000000);
        end
    endtask

    initial begin
        repeat(3) @(negedge clk);rst=0;
        boundary(0);
        sample(0,0,1,24'hff8040,24'h3f2010);
        brightness_level=3;
        sample(0,1,1,24'hff8040,24'h3f2010);
        sample(0,0,0,24'hffffff,24'h000000);
        boundary(1);
        sample(0,0,1,24'hff8040,24'h7f4020);
        boundary(2);
        sample(0,0,1,24'hff8040,24'hbf6030);
        boundary(3);
        sample(0,0,1,24'hff8040,24'hff8040);
        @(negedge clk);rst=1;#1;
        if(de_out!==0 || rgb_out!==0) $fatal(1,"reset left brightness output active");
        $display("PASS: E3 25/50/75/100 RGB scaling, blanking, aligned controls and frame-latched updates");
        $finish;
    end
    initial begin #100000; $fatal(1,"E3 brightness timeout"); end
endmodule
