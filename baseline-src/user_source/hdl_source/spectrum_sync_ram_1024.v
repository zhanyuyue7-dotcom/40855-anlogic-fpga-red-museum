// Standalone synchronous single-write/single-read RAM for SP1.
// The marker matches the local Anlogic-generated FIFO template.  TD must report
// an EG_LOGIC_BRAM mapping before this module is considered resource-verified.
module spectrum_sync_ram_1024 #(
    parameter integer DATA_WIDTH = 32
)(
    input  wire                  clk,
    input  wire                  write_en,
    input  wire [9:0]            write_addr,
    input  wire [DATA_WIDTH-1:0] write_data,
    input  wire                  read_en,
    input  wire [9:0]            read_addr,
    output reg  [DATA_WIDTH-1:0] read_data
);
    reg [DATA_WIDTH-1:0] mem [0:1023]; /* fehdl force_ram=1, ram_style="bram" */

    always @(posedge clk) begin
        if (write_en)
            mem[write_addr] <= write_data;
    end

    // Registered synchronous read.  With a simultaneous same-address write,
    // nonblocking assignment gives the NORMAL/read-first old-data behavior.
    always @(posedge clk) begin
        if (read_en)
            read_data <= mem[read_addr];
    end
endmodule
