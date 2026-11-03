`timescale 1ns / 1ps

module w5500_command_decoder_tb;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg packet_start = 1'b0;
    reg data_valid = 1'b0;
    reg [7:0] data = 8'd0;
    wire cmd_next;
    wire cmd_auto_toggle;
    wire cmd_notice;
    wire cmd_clear;
    wire cmd_brightness_up;
    wire cmd_brightness_down;
    wire command_valid;
    wire command_error;
    wire [7:0] command_seq;

    reg [7:0] frame [0:7];
    integer i;
    integer valid_count;
    integer error_count;

    always #10 clk = ~clk;

    w5500_command_decoder dut (
        .clk(clk), .rst(rst), .packet_start(packet_start),
        .data_valid(data_valid), .data(data),
        .cmd_next(cmd_next), .cmd_auto_toggle(cmd_auto_toggle),
        .cmd_notice(cmd_notice), .cmd_clear(cmd_clear),
        .cmd_brightness_up(cmd_brightness_up),
        .cmd_brightness_down(cmd_brightness_down),
        .command_valid(command_valid), .command_error(command_error),
        .command_seq(command_seq)
    );

    function automatic [7:0] crc8;
        input [55:0] bytes;
        integer b;
        integer k;
        reg [7:0] c;
        reg [7:0] d;
        begin
            c = 0;
            for (b = 6; b >= 0; b = b - 1) begin
                d = bytes[b*8 +: 8];
                c = c ^ d;
                for (k = 0; k < 8; k = k + 1)
                    c = c[7] ? ((c << 1) ^ 8'h07) : (c << 1);
            end
            crc8 = c;
        end
    endfunction

    task send_command;
        input [7:0] seq;
        input [7:0] opcode;
        input corrupt;
        reg [55:0] first_seven;
        begin
            frame[0] = 8'ha5;
            frame[1] = 8'h01;
            frame[2] = seq;
            frame[3] = opcode;
            frame[4] = 8'h00;
            frame[5] = 8'h00;
            frame[6] = 8'h00;
            first_seven = {frame[0], frame[1], frame[2], frame[3], frame[4], frame[5], frame[6]};
            frame[7] = crc8(first_seven) ^ (corrupt ? 8'h01 : 8'h00);
            @(posedge clk);
            packet_start <= 1'b1;
            @(posedge clk);
            packet_start <= 1'b0;
            for (i = 0; i < 8; i = i + 1) begin
                data <= frame[i];
                data_valid <= 1'b1;
                @(posedge clk);
            end
            data_valid <= 1'b0;
            data <= 0;
            repeat (2) @(posedge clk);
        end
    endtask

    always @(posedge clk) begin
        if (command_valid) valid_count <= valid_count + 1;
        if (command_error) error_count <= error_count + 1;
    end

    initial begin
        valid_count = 0;
        error_count = 0;
        repeat (4) @(posedge clk);
        rst <= 1'b0;

        send_command(8'h2a, 8'h10, 1'b0);
        if (valid_count !== 1 || command_seq !== 8'h2a) begin
            $display("FAIL: valid next command was not accepted");
            $fatal(1);
        end

        send_command(8'h2b, 8'h20, 1'b1);
        if (valid_count !== 1 || error_count !== 1) begin
            $display("FAIL: corrupt CRC was not rejected valid=%0d error=%0d", valid_count, error_count);
            $fatal(1);
        end

        send_command(8'h2c, 8'h7f, 1'b0);
        if (valid_count !== 1 || error_count !== 2) begin
            $display("FAIL: unknown opcode was not rejected valid=%0d error=%0d", valid_count, error_count);
            $fatal(1);
        end

        $display("PASS: W5500 command framing, CRC and opcode validation");
        $finish;
    end
endmodule
