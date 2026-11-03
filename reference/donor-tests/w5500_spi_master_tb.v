`timescale 1ns / 1ps

module w5500_spi_master_tb;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg start = 1'b0;
    reg write = 1'b0;
    reg [15:0] address = 16'd0;
    reg [4:0] block = 5'd0;
    reg [7:0] write_data = 8'd0;
    reg miso = 1'b0;
    wire busy;
    wire done;
    wire [7:0] read_data;
    wire cs_n;
    wire sclk;
    wire mosi;

    integer rise_count;
    reg [31:0] captured;
    reg [7:0] read_pattern;

    always #10 clk = ~clk;

    w5500_spi_master #(.CLK_DIV(2)) dut (
        .clk(clk), .rst(rst), .start(start), .write(write),
        .address(address), .block(block), .write_data(write_data),
        .busy(busy), .done(done), .read_data(read_data),
        .w5500_cs_n(cs_n), .w5500_sclk(sclk),
        .w5500_mosi(mosi), .w5500_miso(miso)
    );

    always @(posedge sclk) begin
        captured = {captured[30:0], mosi};
        rise_count = rise_count + 1;
    end

    always @(negedge sclk) begin
        if (!write && rise_count >= 24 && rise_count < 32)
            miso <= read_pattern[31 - rise_count];
        else
            miso <= 1'b0;
    end

    task launch;
        begin
            @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;
            wait(done);
            @(posedge clk);
        end
    endtask

    initial begin
        rise_count = 0;
        captured = 0;
        read_pattern = 8'h05;
        repeat (4) @(posedge clk);
        rst <= 1'b0;

        write <= 1'b1;
        address <= 16'h1234;
        block <= 5'h01;
        write_data <= 8'ha5;
        launch();
        if (rise_count !== 32 || captured !== 32'h1234_0ca5) begin
            $display("FAIL: write frame count=%0d frame=%08x", rise_count, captured);
            $fatal(1);
        end
        if (!cs_n || sclk) begin
            $display("FAIL: SPI did not return idle");
            $fatal(1);
        end

        rise_count = 0;
        captured = 0;
        write <= 1'b0;
        address <= 16'h0039;
        block <= 5'h00;
        write_data <= 8'h00;
        launch();
        if (rise_count !== 32 || captured[31:8] !== 24'h0039_00) begin
            $display("FAIL: read header count=%0d frame=%08x", rise_count, captured);
            $fatal(1);
        end
        if (read_data !== 8'h05) begin
            $display("FAIL: read data=%02x", read_data);
            $fatal(1);
        end

        $display("PASS: W5500 SPI single-byte read/write transactions");
        $finish;
    end
endmodule
