`timescale 1ns/1ps
module matrix_keypad_tb;
    reg clk = 0, rst = 1;
    reg [15:0] pressed_keys = 16'd0;
    reg [3:0] rows_n;
    wire [3:0] cols_n;
    wire [15:0] keys_pressed;
    integer key_index;

    matrix_keypad #(.ROW_SCAN_DIV(6), .DEBOUNCE_SCANS(3)) dut(
        .clk(clk), .rst(rst), .rows_n(rows_n), .cols_n(cols_n),
        .keys_pressed(keys_pressed)
    );

    always #5 clk = ~clk;

    function [3:0] derive_rows;
        input [3:0] selected_cols_n;
        input [15:0] keys;
        integer row_index, col_index;
        begin
            derive_rows = 4'b1111;
            for (col_index = 0; col_index < 4; col_index = col_index + 1)
                if (!selected_cols_n[col_index])
                    for (row_index = 0; row_index < 4; row_index = row_index + 1)
                        if (keys[row_index*4+col_index]) derive_rows[row_index] = 1'b0;
        end
    endfunction

    always @* rows_n = derive_rows(cols_n, pressed_keys);

    task clocks;
        input integer count;
        integer i;
        begin
            for (i = 0; i < count; i = i + 1) begin
                @(posedge clk); #1;
            end
        end
    endtask

    initial begin
        clocks(3); rst = 0;
        clocks(40);
        if (keys_pressed !== 16'd0) $fatal(1, "reset/released keypad must be idle");

        pressed_keys = 16'h0001;
        clocks(40);
        pressed_keys = 16'd0;
        clocks(40);
        if (keys_pressed !== 16'd0) $fatal(1, "short S1 bounce was accepted");

        pressed_keys = 16'h0001;
        clocks(120);
        if (keys_pressed !== 16'h0001) $fatal(1, "S1 did not debounce to key bit 0");
        pressed_keys = 16'd0;
        clocks(120);
        if (keys_pressed !== 16'd0) $fatal(1, "S1 release did not debounce");

        pressed_keys = 16'h0002;
        clocks(120);
        if (keys_pressed !== 16'h0002) $fatal(1, "S2 did not debounce to key bit 1");
        pressed_keys = 16'd0;
        clocks(120);

        pressed_keys = 16'h0004;
        clocks(120);
        if (keys_pressed !== 16'h0004) $fatal(1, "S3 did not debounce to key bit 2");
        pressed_keys = 16'd0;
        clocks(120);

        pressed_keys = 16'h0008;
        clocks(120);
        if (keys_pressed !== 16'h0008) $fatal(1, "S4 did not debounce to key bit 3");
        pressed_keys = 16'd0;
        clocks(120);

        pressed_keys = 16'h0003;
        clocks(120);
        if (keys_pressed !== 16'd0) $fatal(1, "ambiguous chord changed the accepted key state");
        pressed_keys = 16'd0;
        clocks(120);
        if (keys_pressed !== 16'd0) $fatal(1, "release after an ambiguous chord was not accepted");

        // Align to column 0, then change the pressed key every complete scan.
        // Different short presses must not accumulate toward one debounce.
        wait (cols_n !== 4'bzzz0);
        wait (cols_n === 4'bzzz0); #1;
        for (key_index = 0; key_index < 12; key_index = key_index + 1) begin
            pressed_keys = 16'h0001 << (key_index % 4);
            clocks(24);
            if (keys_pressed !== 16'd0)
                $fatal(1, "different one-scan presses accumulated into a stable key");
        end
        pressed_keys = 16'd0;
        clocks(120);

        // Check every row/column coordinate, not just the assigned first row.
        for (key_index = 0; key_index < 16; key_index = key_index + 1) begin
            pressed_keys = 16'h0001 << key_index;
            clocks(120);
            if (keys_pressed !== pressed_keys)
                $fatal(1, "key coordinate %0d decoded incorrectly", key_index);
            pressed_keys = 16'd0;
            clocks(120);
            if (keys_pressed !== 16'd0) $fatal(1, "stable release was not accepted");
        end

        pressed_keys = 16'h0001;
        clocks(120);
        pressed_keys = 16'h0003;
        clocks(120);
        if (keys_pressed !== 16'h0001) $fatal(1, "chord did not preserve the accepted key");
        pressed_keys = 16'd0;
        clocks(120);
        if (keys_pressed !== 16'd0) $fatal(1, "held key did not release after chord");

        $display("PASS: all 16 coordinates, stable press/release, changing-key bounce rejection and chord suppression");
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "matrix keypad test timeout");
    end
endmodule
