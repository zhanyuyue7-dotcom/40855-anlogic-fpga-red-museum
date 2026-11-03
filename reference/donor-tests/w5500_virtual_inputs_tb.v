`timescale 1ns / 1ps

module w5500_virtual_inputs_tb;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg cmd_next = 1'b0;
    reg cmd_auto_toggle = 1'b0;
    reg cmd_notice = 1'b0;
    reg cmd_clear = 1'b0;
    reg cmd_brightness_up = 1'b0;
    reg cmd_brightness_down = 1'b0;
    wire key_next_n, key_auto_n, key_event_n, sw_clear;
    wire key_brightness_up_n, key_brightness_down_n;

    always #5 clk = ~clk;

    w5500_virtual_inputs #(.HOLD_CYCLES(3)) dut (
        .clk(clk), .rst(rst), .cmd_next(cmd_next),
        .cmd_auto_toggle(cmd_auto_toggle), .cmd_notice(cmd_notice),
        .cmd_clear(cmd_clear), .cmd_brightness_up(cmd_brightness_up),
        .cmd_brightness_down(cmd_brightness_down),
        .key_next_n(key_next_n), .key_auto_n(key_auto_n),
        .key_event_n(key_event_n), .sw_clear(sw_clear),
        .key_brightness_up_n(key_brightness_up_n),
        .key_brightness_down_n(key_brightness_down_n)
    );

    initial begin
        repeat (2) @(posedge clk);
        rst <= 1'b0;
        if (!key_next_n || sw_clear) $fatal(1, "FAIL: reset levels");
        @(posedge clk); cmd_next <= 1'b1;
        @(posedge clk); cmd_next <= 1'b0;
        #1 if (key_next_n) $fatal(1, "FAIL: next key was not held");
        repeat (2) @(posedge clk);
        #1 if (key_next_n) $fatal(1, "FAIL: next key released too early");
        @(posedge clk); #1 if (!key_next_n) $fatal(1, "FAIL: next key did not release");

        @(posedge clk); cmd_clear <= 1'b1;
        @(posedge clk); cmd_clear <= 1'b0;
        #1 if (!sw_clear) $fatal(1, "FAIL: clear level missing");
        repeat (3) @(posedge clk);
        #1 if (sw_clear) $fatal(1, "FAIL: clear level stuck");
        $display("PASS: network commands become debouncer-compatible levels");
        $finish;
    end
endmodule
