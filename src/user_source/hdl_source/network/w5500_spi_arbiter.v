// Shared W5500 SPI arbiter with legacy register transactions and HTTP bursts.
module w5500_spi_arbiter(
    input wire clk, input wire rst,
    input wire udp_start, input wire udp_write, input wire [15:0] udp_addr,
    input wire [4:0] udp_block, input wire [7:0] udp_wdata,
    output reg udp_done, output reg [7:0] udp_rdata,
    input wire http_start, input wire http_write, input wire [15:0] http_addr,
    input wire [4:0] http_block, input wire [7:0] http_wdata,
    output reg http_done, output reg [7:0] http_rdata,
    output reg spi_start, output reg spi_write, output reg [15:0] spi_addr,
    output reg [4:0] spi_block, output reg [7:0] spi_wdata,
    input wire spi_done, input wire [7:0] spi_rdata,
    input wire http_burst_start, input wire http_burst_write,
    input wire [15:0] http_burst_addr, input wire [4:0] http_burst_block,
    input wire [7:0] http_burst_len, input wire http_burst_tx_valid,
    input wire [7:0] http_burst_tx_data, output reg http_burst_tx_ready,
    output reg http_burst_rx_valid, output reg [7:0] http_burst_rx_data,
    output reg http_burst_done,
    output reg burst_spi_start, output reg burst_spi_write,
    output reg [15:0] burst_spi_addr, output reg [4:0] burst_spi_block,
    output reg [7:0] burst_spi_len, output reg burst_spi_tx_valid,
    output reg [7:0] burst_spi_tx_data, input wire burst_spi_tx_ready,
    input wire burst_spi_rx_valid, input wire [7:0] burst_spi_rx_data,
    input wire burst_spi_done
);
    reg [1:0] owner;
    reg burst_owner;
    reg udp_pending, http_pending;
    reg udp_pending_write, http_pending_write;
    reg [15:0] udp_pending_addr, http_pending_addr;
    reg [4:0] udp_pending_block, http_pending_block;
    reg [7:0] udp_pending_wdata, http_pending_wdata;

    task automatic launch_udp;
        begin
            spi_start <= 1'b1; spi_write <= udp_pending_write;
            spi_addr <= udp_pending_addr; spi_block <= udp_pending_block;
            spi_wdata <= udp_pending_wdata; owner <= 2'd1; udp_pending <= 1'b0;
        end
    endtask
    task automatic launch_http;
        begin
            spi_start <= 1'b1; spi_write <= http_pending_write;
            spi_addr <= http_pending_addr; spi_block <= http_pending_block;
            spi_wdata <= http_pending_wdata; owner <= 2'd2; http_pending <= 1'b0;
        end
    endtask
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            owner <= 2'd0; burst_owner <= 1'b0;
            udp_pending <= 1'b0; http_pending <= 1'b0;
            udp_done <= 1'b0; http_done <= 1'b0;
            udp_rdata <= 8'd0; http_rdata <= 8'd0;
            spi_start <= 1'b0; spi_write <= 1'b0; spi_addr <= 16'd0;
            spi_block <= 5'd0; spi_wdata <= 8'd0;
            udp_pending_write <= 1'b0; http_pending_write <= 1'b0;
            udp_pending_addr <= 16'd0; http_pending_addr <= 16'd0;
            udp_pending_block <= 5'd0; http_pending_block <= 5'd0;
            udp_pending_wdata <= 8'd0; http_pending_wdata <= 8'd0;
            http_burst_tx_ready <= 1'b0; http_burst_rx_valid <= 1'b0;
            http_burst_rx_data <= 8'd0; http_burst_done <= 1'b0;
            burst_spi_start <= 1'b0; burst_spi_write <= 1'b0;
            burst_spi_addr <= 16'd0; burst_spi_block <= 5'd0;
            burst_spi_len <= 8'd0; burst_spi_tx_valid <= 1'b0;
            burst_spi_tx_data <= 8'd0;
        end else begin
            spi_start <= 1'b0; burst_spi_start <= 1'b0;
            udp_done <= 1'b0; http_done <= 1'b0;
            http_burst_done <= 1'b0; http_burst_rx_valid <= 1'b0;
            http_burst_tx_ready <= 1'b0;

            if(burst_owner && udp_start && !udp_pending)begin
                udp_pending<=1;udp_pending_write<=udp_write;udp_pending_addr<=udp_addr;
                udp_pending_block<=udp_block;udp_pending_wdata<=udp_wdata;
            end
            if(burst_owner && http_start && !http_pending)begin
                http_pending<=1;http_pending_write<=http_write;http_pending_addr<=http_addr;
                http_pending_block<=http_block;http_pending_wdata<=http_wdata;
            end
            if (burst_owner) begin
                burst_spi_tx_valid <= http_burst_tx_valid;
                burst_spi_tx_data <= http_burst_tx_data;
                http_burst_tx_ready <= burst_spi_tx_ready;
                if (burst_spi_rx_valid) begin
                    http_burst_rx_valid <= 1'b1;
                    http_burst_rx_data <= burst_spi_rx_data;
                end
                if (burst_spi_done) begin
                    burst_owner <= 1'b0;
                    burst_spi_tx_valid <= 1'b0;
                    http_burst_done <= 1'b1;
                end
            end else begin
                if (http_burst_start && owner == 2'd0 && !udp_pending && !http_pending) begin
                    burst_owner <= 1'b1;
                    burst_spi_start <= 1'b1;
                    burst_spi_write <= http_burst_write;
                    burst_spi_addr <= http_burst_addr;
                    burst_spi_block <= http_burst_block;
                    burst_spi_len <= http_burst_len;
                    burst_spi_tx_valid <= http_burst_tx_valid;
                    burst_spi_tx_data <= http_burst_tx_data;
                end
                if (udp_start) begin
                    if (owner == 2'd0 && !udp_pending && !http_pending && !http_burst_start) begin
                        spi_start <= 1'b1; spi_write <= udp_write;
                        spi_addr <= udp_addr; spi_block <= udp_block;
                        spi_wdata <= udp_wdata; owner <= 2'd1;
                    end else if (!udp_pending) begin
                        udp_pending <= 1'b1; udp_pending_write <= udp_write;
                        udp_pending_addr <= udp_addr; udp_pending_block <= udp_block;
                        udp_pending_wdata <= udp_wdata;
                    end
                end
                if (http_start) begin
                    if (owner == 2'd0 && !udp_pending && !http_pending && !udp_start && !http_burst_start) begin
                        spi_start <= 1'b1; spi_write <= http_write;
                        spi_addr <= http_addr; spi_block <= http_block;
                        spi_wdata <= http_wdata; owner <= 2'd2;
                    end else if (!http_pending) begin
                        http_pending <= 1'b1; http_pending_write <= http_write;
                        http_pending_addr <= http_addr; http_pending_block <= http_block;
                        http_pending_wdata <= http_wdata;
                    end
                end
                if (spi_done && owner != 2'd0) begin
                    if (owner == 2'd1) begin udp_done <= 1'b1; udp_rdata <= spi_rdata; end
                    else begin http_done <= 1'b1; http_rdata <= spi_rdata; end
                    owner <= 2'd0;
                end else if (owner == 2'd0 && !udp_start && !http_start && !http_burst_start) begin
                    if (udp_pending) launch_udp();
                    else if (http_pending) launch_http();
                end
            end
        end
    end
endmodule
