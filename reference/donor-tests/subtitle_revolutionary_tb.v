`timescale 1ns/1ps
module subtitle_revolutionary_tb;
    reg clk=0, rst=1, hs=0, vs=1, de=0;
    reg [23:0] rgb=24'h123456;
    reg [1:0] scene=0;
    reg [3:0] state=1;
    reg [1:0] brightness=0;
    reg adjust=0;
    wire ohs, ovs, ode;
    wire [23:0] out_rgb;
    integer checked=0;
    reg [23:0] expected;
    subtitle_osd dut(.clk(clk),.rst(rst),.hs(hs),.vs(vs),.de(de),.rgb(rgb),
        .scene_id(scene),.run_state(state),.brightness_level(brightness),
        .adjust_mode(adjust),.ui_fade_level(6'd32),.hs_out(ohs),.vs_out(ovs),.de_out(ode),.rgb_out(out_rgb));
    always #5 clk=~clk;

    function [23:0] expected_at;
        input integer px, py;
        begin
            expected_at=24'h123456;
            if (py < 36) begin
                if (py == 35) expected_at=24'h8b0000; else expected_at=24'hf5e6d3;
            end else if (py >= 408 && py < 440) begin
                if (py == 408 || py == 440) expected_at=24'h8b0000; else expected_at=24'hf5e6d3;
            end else if (py >= 440) begin
                expected_at=py == 440 ? 24'h8b0000 : 24'hf5e6d3;
                if ((px==155 || px==410) && py>=450 && py<474) expected_at=24'h8b0000;
                if (px>=260 && px<380 && py>=456 && py<464) begin
                    if (px<262 || px>=378 || py<458 || py>=462) expected_at=24'h8b0000;
                    else if (px < 262 + (brightness==2'd0 ? 29 : brightness==2'd1 ? 58 : brightness==2'd2 ? 87 : 116)) expected_at=24'h8b0000;
                end
            end
        end
    endfunction

    task sample;
        input integer px, py;
        begin
            force dut.x=px; force dut.y=py;
            @(negedge clk); de=1; #1;
            @(posedge clk); #1;
            if (ode !== 1'b1) $fatal(1,"DE mismatch at %0d,%0d",px,py);
            expected=expected_at(px,py);
            if (out_rgb !== expected)
                $fatal(1,"pixel mismatch at %0d,%0d got %h expected %h",px,py,out_rgb,expected);
            checked=checked+1;
            @(negedge clk); de=0;
            release dut.x; release dut.y;
        end
    endtask

    task bar_check;
        input [1:0] br;
        input integer inside_px, outside_px;
        begin
            brightness=br;
            force dut.frame_brightness=br;
            sample(inside_px,458);
            sample(outside_px,458);
            release dut.frame_brightness;
        end
    endtask

    initial begin
        repeat(3) @(negedge clk); rst=0;
        // One blanking interval latches ordinary scene and metadata.
        repeat(4) begin @(negedge clk); vs=1; de=0; end
        @(negedge clk); vs=0; de=0;
        repeat(8) @(negedge clk);
        sample(10,0); sample(10,35); sample(10,36); sample(10,408); sample(10,412); sample(10,440); sample(10,442); sample(155,452); sample(410,452); sample(260,456); sample(262,458); sample(290,458); sample(319,458); sample(320,458); sample(377,461);
        bar_check(2'd0,290,291); bar_check(2'd1,319,320); bar_check(2'd2,348,349); bar_check(2'd3,377,378);
        if (checked != 23) $fatal(1,"insufficient layout coverage");
        $display("PASS: revolutionary layout and continuous bar geometry");
        $finish;
    end
    initial begin #1000000; $fatal(1,"timeout"); end
endmodule
