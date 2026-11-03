`timescale 1ns/1ps

module uart_status_tb;

localparam integer CLK_FREQ_HZ = 1_000_000;
localparam integer BAUD_RATE   = 100_000;
localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;

reg clk = 1'b0;
reg rst = 1'b1;
reg [3:0] state_code = 4'h1;
reg [2:0] found_count = 3'h4;
reg [1:0] image_index = 2'h2;
reg auto_play = 1'b1;
reg load_busy = 1'b0;
reg display_valid = 1'b1;
reg sd_init_done = 1'b1;
reg scan_done = 1'b1;
reg [1:0] disp_buf_idx = 2'h1;
reg [1:0] write_buf_idx = 2'h0;
wire uart_tx;

integer i;
integer errors = 0;
reg [7:0] received;
reg [7:0] expected [0:22];

always #500 clk = ~clk;

lab4_status_uart #(
    .CLK_FREQ_HZ      (CLK_FREQ_HZ),
    .BAUD_RATE        (BAUD_RATE),
    .MIN_GAP_CYCLES   (10),
    .HEARTBEAT_CYCLES (10000)
) dut (
    .clk           (clk),
    .rst           (rst),
    .state_code    (state_code),
    .found_count   (found_count),
    .image_index   (image_index),
    .auto_play     (auto_play),
    .load_busy     (load_busy),
    .display_valid (display_valid),
    .sd_init_done  (sd_init_done),
    .scan_done     (scan_done),
    .disp_buf_idx  (disp_buf_idx),
    .write_buf_idx (write_buf_idx),
    .uart_tx       (uart_tx)
);

task receive_byte;
    output [7:0] value;
    integer bit_number;
    begin
        @(negedge uart_tx);
        repeat (CLKS_PER_BIT + CLKS_PER_BIT/2) @(posedge clk);
        for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
            value[bit_number] = uart_tx;
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
        if (uart_tx !== 1'b1) begin
            $display("UART stop bit error");
            errors = errors + 1;
        end
    end
endtask

initial begin
    expected[0]  = "@";
    expected[1]  = "S";
    expected[2]  = ",";
    expected[3]  = "1";
    expected[4]  = ",";
    expected[5]  = "4";
    expected[6]  = ",";
    expected[7]  = "2";
    expected[8]  = ",";
    expected[9]  = "1";
    expected[10] = ",";
    expected[11] = "0";
    expected[12] = ",";
    expected[13] = "1";
    expected[14] = ",";
    expected[15] = "1";
    expected[16] = ",";
    expected[17] = "1";
    expected[18] = ",";
    expected[19] = "1";
    expected[20] = ",";
    expected[21] = "0";
    expected[22] = 8'h0A;

    repeat (5) @(posedge clk);
    rst = 1'b0;

    for (i = 0; i < 23; i = i + 1) begin
        receive_byte(received);
        if (received !== expected[i]) begin
            $display("BYTE MISMATCH index=%0d got=0x%02x expected=0x%02x", i, received, expected[i]);
            errors = errors + 1;
        end
    end

    if (errors)
        $fatal(1, "FAIL UART packet errors=%0d", errors);

    $display("PASS: compact 23-byte UART status packet decoded exactly");
    $finish;
end

endmodule
