module w5500_web_rom #(
    parameter integer DEPTH = 4096,
    parameter INIT_FILE = "../user_source/hdl_source/network/w5500_web_response.hex"
)(
    input  wire [11:0] address,
    output wire [7:0]  data
);
    reg [7:0] memory [0:DEPTH-1];
    initial begin
        $readmemh(INIT_FILE, memory);
    end
    assign data = memory[address];
endmodule
