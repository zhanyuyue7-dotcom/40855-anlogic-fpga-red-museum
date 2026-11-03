// E3: frame-stable four-level RGB brightness stage. The selected level is
// captured only at the vertical blanking boundary, so a control change cannot
// split one visible frame into two brightness values.
module video_brightness(
    input  wire        clk,
    input  wire        rst,
    input  wire        hs,
    input  wire        vs,
    input  wire        de,
    input  wire [23:0] rgb,
    input  wire [1:0]  brightness_level,
    output reg         hs_out,
    output reg         vs_out,
    output reg         de_out,
    output reg  [23:0] rgb_out
);
    reg vs_prev;
    reg [1:0] frame_level;
    wire frame_boundary = vs_prev && !vs && !de;

    function [7:0] scale_channel;
        input [7:0] channel;
        input [1:0] level;
        reg [9:0] triple;
        begin
            triple = {2'b00,channel} + ({2'b00,channel} << 1);
            case (level)
                2'd0: scale_channel = channel >> 2;  // 25%
                2'd1: scale_channel = channel >> 1;  // 50%
                2'd2: scale_channel = triple >> 2;   // 75%
                default: scale_channel = channel;    // 100%
            endcase
        end
    endfunction

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            vs_prev <= 1'b0;
            frame_level <= 2'd3;
            hs_out <= 1'b0;
            vs_out <= 1'b0;
            de_out <= 1'b0;
            rgb_out <= 24'd0;
        end else begin
            vs_prev <= vs;
            if (frame_boundary)
                frame_level <= brightness_level;
            hs_out <= hs;
            vs_out <= vs;
            de_out <= de;
            rgb_out <= de ? {
                scale_channel(rgb[23:16],frame_level),
                scale_channel(rgb[15:8],frame_level),
                scale_channel(rgb[7:0],frame_level)
            } : 24'd0;
        end
    end
endmodule
