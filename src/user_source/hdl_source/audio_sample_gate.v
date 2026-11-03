// Keep the HDMI audio packet cadence alive while replacing samples with
// digital silence. SW4 is synchronized/debounced before reaching enable.
module audio_sample_gate(
    input  wire        enable,
    input  wire        valid_in,
    input  wire [23:0] left_in,
    input  wire [23:0] right_in,
    output wire        valid_out,
    output wire [23:0] left_out,
    output wire [23:0] right_out
);
    assign valid_out = valid_in;
    assign left_out = enable ? left_in : 24'd0;
    assign right_out = enable ? right_in : 24'd0;
endmodule
