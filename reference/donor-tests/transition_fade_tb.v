`timescale 1ns/1ps
module transition_fade_tb;
    reg clk = 0;
    reg rst = 1;
    reg vs = 1;
    reg de = 0;
    reg [23:0] rgb_in = 24'hcc8844;
    reg start_toggle = 0;
    reg commit_toggle = 0;
    wire [23:0] rgb_out;
    wire [5:0] fade_level;
    wire transition_active;
    wire [23:0] bypass_rgb;

    transition_fade #(.SMOOTH(0), .FRAME_HOLD(2), .LEVEL_HOLD(2), .ENABLE(1)) dut(
        .clk(clk), .rst(rst), .vs(vs), .de(de), .rgb_in(rgb_in),
        .start_toggle(start_toggle), .commit_toggle(commit_toggle), .abort_transition(1'b0),
        .rgb_out(rgb_out), .fade_level(fade_level),
        .transition_active(transition_active)
    );
    transition_fade #(.SMOOTH(0), .FRAME_HOLD(1), .ENABLE(0)) bypass(
        .clk(clk), .rst(rst), .vs(vs), .de(de), .rgb_in(rgb_in),
        .start_toggle(start_toggle), .commit_toggle(commit_toggle), .abort_transition(1'b0),
        .rgb_out(bypass_rgb), .fade_level(), .transition_active()
    );

    always #5 clk = ~clk;

    task wait_cycles;
        input integer count;
        integer i;
        begin
            for (i = 0; i < count; i = i + 1)
                @(posedge clk);
        end
    endtask

    task frame_boundary;
        begin
            @(negedge clk); vs = 1'b1; de = 1'b0;
            @(posedge clk);
            @(negedge clk); vs = 1'b0; de = 1'b0;
            @(posedge clk); #1;
        end
    endtask

    task expect_rgb;
        input [23:0] expected;
        input [1:0] expected_level;
        begin
            de = 1'b1;
            #1;
            if (rgb_out !== expected || fade_level !== expected_level)
                $fatal(1, "expected rgb=%h level=%0d, got rgb=%h level=%0d",
                    expected, expected_level, rgb_out, fade_level);
            if (bypass_rgb !== rgb_in)
                $fatal(1, "bypass changed rgb from %h to %h", rgb_in, bypass_rgb);
        end
    endtask

    initial begin
        wait_cycles(3);
        rst = 0;
        wait_cycles(3);
        expect_rgb(24'hcc8844, 2'd3);

        // A subsequent image load starts the fade-out from the current image.
        start_toggle = 1;
        wait_cycles(3);
        frame_boundary();
        expect_rgb(24'hcc8844, 2'd3);
        frame_boundary();
        expect_rgb(24'h664422, 2'd2);
        frame_boundary();
        expect_rgb(24'h664422, 2'd2);
        frame_boundary();
        expect_rgb(24'h332211, 2'd1);
        frame_boundary();
        expect_rgb(24'h332211, 2'd1);
        frame_boundary();
        expect_rgb(24'h000000, 2'd0);
        frame_boundary();
        expect_rgb(24'h000000, 2'd0);

        // The committed buffer gets one complete black protection frame.
        commit_toggle = 1;
        wait_cycles(3);
        frame_boundary();
        expect_rgb(24'h000000, 2'd0);
        frame_boundary();
        expect_rgb(24'h000000, 2'd0);
        frame_boundary();
        expect_rgb(24'h332211, 2'd1);
        frame_boundary();
        expect_rgb(24'h332211, 2'd1);
        frame_boundary();
        expect_rgb(24'h664422, 2'd2);
        frame_boundary();
        expect_rgb(24'h664422, 2'd2);
        frame_boundary();
        expect_rgb(24'hcc8844, 2'd3);
        if (transition_active)
            $fatal(1, "transition remained active after fade-in");

        $display("PASS: fade-out, black protection frame, fade-in and compile-time bypass");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "transition fade timeout");
    end
endmodule
