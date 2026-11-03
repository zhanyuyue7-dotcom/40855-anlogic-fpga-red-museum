`timescale 1ns/1ps
module transition_fade_long_commit_tb;
    reg clk = 0;
    reg rst = 1;
    reg vs = 1;
    reg de = 0;
    reg [23:0] rgb_in = 24'hcc8844;
    reg start_toggle = 0;
    reg commit_toggle = 0;
    wire [23:0] rgb_out;
    wire [5:0] fade_level;

    transition_fade #(.SMOOTH(0), .FRAME_HOLD(2), .LEVEL_HOLD(2), .ENABLE(1)) dut(
        .clk(clk), .rst(rst), .vs(vs), .de(de), .rgb_in(rgb_in),
        .start_toggle(start_toggle), .commit_toggle(commit_toggle), .abort_transition(1'b0),
        .rgb_out(rgb_out), .fade_level(fade_level),
        .transition_active()
    );

    always #5 clk = ~clk;

    task tick;
        begin
            @(posedge clk);
            #1;
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

    task expect_black;
        begin
            de = 1'b1;
            #1;
            if (fade_level !== 2'd0 || rgb_out !== 24'h000000)
                $fatal(1, "expected held black before commit, got level=%0d rgb=%h",
                    fade_level, rgb_out);
        end
    endtask

    initial begin
        repeat (3) tick;
        rst = 1'b0;
        repeat (3) tick;

        start_toggle = 1'b1;
        repeat (3) tick;

        // Reach black, then model a slow SD/SDRAM load. No commit arrives.
        repeat (6) frame_boundary;
        expect_black;
        repeat (8) begin
            frame_boundary;
            expect_black;
        end

        // Once the new buffer is committed, fade-in may begin.
        rgb_in = 24'h3366cc;
        commit_toggle = 1'b1;
        repeat (3) tick;
        frame_boundary;
        expect_black;
        frame_boundary;
        expect_black;
        frame_boundary;
        de = 1'b1;
        #1;
        if (fade_level !== 2'd1 || rgb_out !== 24'h0c1933)
            $fatal(1, "fade-in did not start from the new frame, level=%0d rgb=%h",
                fade_level, rgb_out);

        $display("PASS: fade-out remains black until commit, then fades in the new frame");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "long commit fade timeout");
    end
endmodule
