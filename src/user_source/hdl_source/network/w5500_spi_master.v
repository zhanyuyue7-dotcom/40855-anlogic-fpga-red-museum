// Minimal W5500 SPI mode-0 master for one-byte register/buffer transactions.
// The caller keeps CS low for the complete 16-bit address + control + data frame.
module w5500_spi_legacy_master #(
    parameter integer CLK_DIV = 4
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire        write,
    input  wire [15:0] address,
    input  wire [4:0]  block,
    input  wire [7:0]  write_data,
    output reg         busy,
    output reg         done,
    output reg  [7:0]  read_data,
    output reg         w5500_cs_n,
    output reg         w5500_sclk,
    output reg         w5500_mosi,
    input  wire        w5500_miso
);
    localparam integer DIV_W = (CLK_DIV <= 1) ? 1 : $clog2(CLK_DIV);
    reg [DIV_W-1:0] div_count;
    reg phase;
    reg [5:0] bit_count;
    reg [31:0] tx_shift;
    reg [31:0] rx_shift;

    wire [7:0] control = {block, write, 2'b00};

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            busy         <= 1'b0;
            done         <= 1'b0;
            read_data    <= 8'd0;
            w5500_cs_n   <= 1'b1;
            w5500_sclk   <= 1'b0;
            w5500_mosi   <= 1'b0;
            div_count    <= 'd0;
            phase        <= 1'b0;
            bit_count    <= 6'd0;
            tx_shift     <= 32'd0;
            rx_shift     <= 32'd0;
        end else begin
            done <= 1'b0;
            if (!busy) begin
                w5500_cs_n <= 1'b1;
                w5500_sclk <= 1'b0;
                w5500_mosi <= 1'b0;
                div_count  <= 'd0;
                phase      <= 1'b0;
                if (start) begin
                    busy       <= 1'b1;
                    w5500_cs_n <= 1'b0;
                    bit_count  <= 6'd31;
                    tx_shift   <= {address, control, write_data};
                    w5500_mosi <= address[15];
                    rx_shift   <= 32'd0;
                end
            end else if (div_count == CLK_DIV-1) begin
                div_count <= 'd0;
                if (!phase) begin
                    // Mode 0: MOSI was prepared during the preceding low phase.
                    rx_shift[bit_count] <= w5500_miso;
                    w5500_sclk       <= 1'b1;
                    phase            <= 1'b1;
                end else begin
                    w5500_sclk <= 1'b0;
                    phase      <= 1'b0;
                    if (bit_count == 0) begin
                        busy       <= 1'b0;
                        done       <= 1'b1;
                        read_data  <= rx_shift[7:0];
                        w5500_cs_n <= 1'b1;
                        w5500_mosi <= 1'b0;
                    end else begin
                        bit_count <= bit_count - 1'b1;
                        w5500_mosi <= tx_shift[bit_count - 1'b1];
                    end
                end
            end else begin
                div_count <= div_count + 1'b1;
            end
        end
    end
endmodule

// W5500 variable-data-mode burst writer/reader. The 24-bit address/control
// header is sent once, then up to 255 payload bytes stay under one CS window.
// Writes use a ready/valid byte stream so the HTTP controller can feed ROM data
// without allocating a 2 KiB register array.
module w5500_spi_burst_master #(
    parameter integer CLK_DIV = 4
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire        write,
    input  wire [15:0] address,
    input  wire [4:0]  block,
    input  wire [7:0]  length,
    input  wire        tx_valid,
    input  wire [7:0]  tx_data,
    output reg         tx_ready,
    output reg         rx_valid,
    output reg  [7:0]  rx_data,
    output reg         done,
    output reg         busy,
    output reg         w5500_cs_n,
    output reg         w5500_sclk,
    output reg         w5500_mosi,
    input  wire        w5500_miso
);
    localparam integer DIV_W = (CLK_DIV <= 1) ? 1 : $clog2(CLK_DIV);
    localparam [1:0] ST_IDLE = 2'd0, ST_HEADER = 2'd1,
                     ST_DATA = 2'd2;
    reg [1:0] state;
    reg [DIV_W-1:0] div_count;
    reg phase;
    reg [5:0] bit_count;
    reg [23:0] header_shift;
    reg [7:0] tx_shift, rx_shift;
    reg [7:0] remaining;
    reg write_latched;
    reg waiting_byte;
    wire [7:0] control = {block, write, 2'b00};

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= ST_IDLE;
            div_count    <= 'd0;
            phase        <= 1'b0;
            bit_count    <= 6'd0;
            header_shift <= 24'd0;
            tx_shift     <= 8'd0;
            rx_shift     <= 8'd0;
            remaining    <= 8'd0;
            write_latched<= 1'b0;
            waiting_byte <= 1'b0;
            tx_ready     <= 1'b0;
            rx_valid     <= 1'b0;
            rx_data      <= 8'd0;
            done         <= 1'b0;
            busy         <= 1'b0;
            w5500_cs_n   <= 1'b1;
            w5500_sclk   <= 1'b0;
            w5500_mosi   <= 1'b0;
        end else begin
            done     <= 1'b0;
            rx_valid <= 1'b0;
            if (!busy) begin
                tx_ready   <= 1'b0;
                w5500_cs_n <= 1'b1;
                w5500_sclk <= 1'b0;
                w5500_mosi <= 1'b0;
                div_count  <= 'd0;
                phase      <= 1'b0;
                if (start && (length != 0)) begin
                    busy          <= 1'b1;
                    write_latched <= write;
                    remaining     <= length;
                    header_shift  <= {address, control};
                    bit_count     <= 6'd23;
                    w5500_cs_n    <= 1'b0;
                    w5500_mosi    <= address[15];
                    state         <= ST_HEADER;
                end
            end else if (state == ST_DATA && waiting_byte) begin
                // Keep CS and SCLK idle-low while waiting for the next ROM byte.
                div_count <= 'd0;
                phase     <= 1'b0;
                w5500_sclk<= 1'b0;
                if (tx_valid) begin
                    tx_ready     <= 1'b0;
                    waiting_byte  <= 1'b0;
                    tx_shift      <= tx_data;
                    bit_count     <= 6'd7;
                    w5500_mosi    <= tx_data[7];
                end else begin
                    tx_ready <= 1'b1;
                end
            end else if (div_count == CLK_DIV-1) begin
                div_count <= 'd0;
                if (!phase) begin
                    if (state == ST_DATA && !write_latched)
                        rx_shift[bit_count] <= w5500_miso;
                    w5500_sclk <= 1'b1;
                    phase      <= 1'b1;
                end else begin
                    w5500_sclk <= 1'b0;
                    phase      <= 1'b0;
                    if (state == ST_HEADER) begin
                        if (bit_count == 0) begin
                            state <= ST_DATA;
                            if (write_latched) begin
                                waiting_byte <= 1'b1;
                                tx_ready     <= 1'b1;
                                w5500_mosi   <= 1'b0;
                            end else begin
                                bit_count   <= 6'd7;
                                tx_shift    <= 8'd0;
                                w5500_mosi  <= 1'b0;
                            end
                        end else begin
                            bit_count  <= bit_count - 1'b1;
                            w5500_mosi <= header_shift[bit_count - 1'b1];
                        end
                    end else if (bit_count == 0) begin
                        if (!write_latched) begin
                            rx_data  <= rx_shift;
                            rx_valid <= 1'b1;
                        end
                        if (remaining == 1) begin
                            busy       <= 1'b0;
                            done       <= 1'b1;
                            tx_ready   <= 1'b0;
                            w5500_cs_n <= 1'b1;
                            w5500_mosi <= 1'b0;
                            state      <= ST_IDLE;
                        end else begin
                            remaining <= remaining - 1'b1;
                            if (write_latched) begin
                                waiting_byte <= 1'b1;
                                tx_ready     <= 1'b1;
                                w5500_mosi   <= 1'b0;
                            end else begin
                                bit_count  <= 6'd7;
                                tx_shift   <= 8'd0;
                                w5500_mosi <= 1'b0;
                            end
                        end
                    end else begin
                        bit_count  <= bit_count - 1'b1;
                        w5500_mosi <= tx_shift[bit_count - 1'b1];
                    end
                end
            end else begin
                div_count <= div_count + 1'b1;
            end
        end
    end
endmodule

// Compatibility wrapper: the original single-byte interface remains intact;
// the optional burst ports are used by the optimized HTTP path.
module w5500_spi_master #(
    parameter integer CLK_DIV = 4
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire        write,
    input  wire [15:0] address,
    input  wire [4:0]  block,
    input  wire [7:0]  write_data,
    output wire        busy,
    output wire        done,
    output wire [7:0]  read_data,
    output wire        w5500_cs_n,
    output wire        w5500_sclk,
    output wire        w5500_mosi,
    input  wire        w5500_miso,
    input  wire        burst_start,
    input  wire        burst_write,
    input  wire [15:0] burst_address,
    input  wire [4:0]  burst_block,
    input  wire [7:0]  burst_length,
    input  wire        burst_tx_valid,
    input  wire [7:0]  burst_tx_data,
    output wire        burst_tx_ready,
    output wire        burst_rx_valid,
    output wire [7:0]  burst_rx_data,
    output wire        burst_done
);
    wire legacy_busy, legacy_done;
    wire [7:0] legacy_read_data;
    wire legacy_cs_n, legacy_sclk, legacy_mosi;
    wire burst_busy, burst_done_i, burst_cs_n, burst_sclk, burst_mosi;
    wire burst_req = (burst_start === 1'b1);
    wire use_burst = burst_req | burst_busy;

    w5500_spi_legacy_master #(.CLK_DIV(CLK_DIV)) u_legacy(
        .clk(clk), .rst(rst), .start(start && !use_burst), .write(write),
        .address(address), .block(block), .write_data(write_data),
        .busy(legacy_busy), .done(legacy_done), .read_data(legacy_read_data),
        .w5500_cs_n(legacy_cs_n), .w5500_sclk(legacy_sclk),
        .w5500_mosi(legacy_mosi), .w5500_miso(w5500_miso)
    );
    w5500_spi_burst_master #(.CLK_DIV(CLK_DIV)) u_burst(
        .clk(clk), .rst(rst), .start(burst_start), .write(burst_write),
        .address(burst_address), .block(burst_block), .length(burst_length),
        .tx_valid(burst_tx_valid), .tx_data(burst_tx_data),
        .tx_ready(burst_tx_ready), .rx_valid(burst_rx_valid),
        .rx_data(burst_rx_data), .done(burst_done_i), .busy(burst_busy),
        .w5500_cs_n(burst_cs_n), .w5500_sclk(burst_sclk),
        .w5500_mosi(burst_mosi), .w5500_miso(w5500_miso)
    );
    assign busy       = use_burst ? burst_busy : legacy_busy;
    assign done       = use_burst ? 1'b0 : legacy_done;
    assign read_data  = legacy_read_data;
    assign w5500_cs_n = use_burst ? burst_cs_n : legacy_cs_n;
    assign w5500_sclk = use_burst ? burst_sclk : legacy_sclk;
    assign w5500_mosi = use_burst ? burst_mosi : legacy_mosi;
    assign burst_done = burst_done_i;
endmodule
