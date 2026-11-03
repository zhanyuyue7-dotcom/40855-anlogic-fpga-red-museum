// Stable SD-domain fault snapshot mailbox for video-domain telemetry.
// The source fields remain held until the existing toggle/ACK mailbox accepts
// them, so fault/code/recovery cannot be sampled as independent asynchronous bits.
module storage_fault_cdc(
    input  wire       source_clk,
    input  wire       pixel_clk,
    input  wire       rst,
    input  wire       source_fault,
    input  wire [2:0] source_code,
    input  wire [7:0] source_recovery,
    output wire       pixel_fault,
    output wire [2:0] pixel_code,
    output wire [7:0] pixel_recovery
);
    wire [11:0] source_snapshot;
    wire [11:0] pixel_snapshot;

    assign source_snapshot = {source_fault, source_code, source_recovery};
    assign pixel_fault = pixel_snapshot[11];
    assign pixel_code = pixel_snapshot[10:8];
    assign pixel_recovery = pixel_snapshot[7:0];

    osd_status_cdc #(.WIDTH(12), .ONLY_ON_CHANGE(0)) u_snapshot(
        .source_clk(source_clk),
        .pixel_clk(pixel_clk),
        .rst(rst),
        .source_state(source_snapshot),
        .pixel_state(pixel_snapshot)
    );
endmodule
