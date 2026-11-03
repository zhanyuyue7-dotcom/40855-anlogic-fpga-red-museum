// Frame-safe 64-column spectrum overlay.
// The FFT/analysis side supplies one packed 64x8-bit snapshot. This module
// commits it only at a vertical blanking boundary and never touches the
// existing audio or frame-buffer paths.
module spectrum_overlay #(
    parameter integer FRAME_WIDTH = 640,
    parameter integer FRAME_HEIGHT = 480,
    parameter integer X0 = 32,
    parameter integer Y0 = 280,
    parameter integer WIDTH = 576,
    parameter integer HEIGHT = 160,
    // 0 preserves the SP3 accepted gold overlay; 1 selects the portable
    // 64-entry RGB rainbow table for the 1024-point spectrum candidate.
    parameter integer COLOR_MODE = 0
)(
    input  wire         clk,
    input  wire         rst,
    input  wire         hs,
    input  wire         vs,
    input  wire         de,
    input  wire [23:0]  rgb_in,
    input  wire [1:0]   scene_id,
    input  wire [5:0]   ui_fade_level,
    input  wire         s8_event,
    input  wire         snapshot_valid,
    input  wire [511:0] snapshot_heights,
    output reg          hs_out,
    output reg          vs_out,
    output reg          de_out,
    output reg [23:0]   rgb_out,
    output reg          enabled
);

localparam integer BAR_WIDTH = WIDTH / 64;
reg [511:0] pending_heights;
reg [511:0] frame_heights;
reg pending_valid;
reg vs_prev;
reg de_prev;
reg [10:0] x;
reg [9:0] y;
reg frame_enabled;

wire frame_boundary = vs_prev && !vs && !de;
wire ordinary_scene = (scene_id == 2'd0);
wire ordinary_hidden = ordinary_scene && (ui_fade_level == 6'd0);

function automatic [7:0] height_at;
    input [511:0] packed_value;
    input integer index;
    begin
        height_at = packed_value[index*8 +: 8];
    end
endfunction

function automatic [23:0] spectrum_color_at;
    input integer index;
    begin
        if (COLOR_MODE == 0) begin
            spectrum_color_at = 24'he0a020;
        end else begin
            // S=100%, L=50%, H=360*index/64; generated offline and kept as
            // a constant case table so the pixel path has no HSL arithmetic.
            case (index)
                0:  spectrum_color_at = 24'hff0000;  1:  spectrum_color_at = 24'hff1800;
                2:  spectrum_color_at = 24'hff3000;  3:  spectrum_color_at = 24'hff4800;
                4:  spectrum_color_at = 24'hff6000;  5:  spectrum_color_at = 24'hff7800;
                6:  spectrum_color_at = 24'hff8f00;  7:  spectrum_color_at = 24'hffa700;
                8:  spectrum_color_at = 24'hffbf00;  9:  spectrum_color_at = 24'hffd700;
                10: spectrum_color_at = 24'hffef00; 11: spectrum_color_at = 24'hefef00;
                12: spectrum_color_at = 24'hdfff00; 13: spectrum_color_at = 24'hc7ff00;
                14: spectrum_color_at = 24'hafff00; 15: spectrum_color_at = 24'h97ff00;
                16: spectrum_color_at = 24'h80ff00; 17: spectrum_color_at = 24'h68ff00;
                18: spectrum_color_at = 24'h50ff00; 19: spectrum_color_at = 24'h38ff00;
                20: spectrum_color_at = 24'h20ff00; 21: spectrum_color_at = 24'h08ff08;
                22: spectrum_color_at = 24'h00ff10; 23: spectrum_color_at = 24'h00ff28;
                24: spectrum_color_at = 24'h00ff40; 25: spectrum_color_at = 24'h00ff58;
                26: spectrum_color_at = 24'h00ff70; 27: spectrum_color_at = 24'h00ff88;
                28: spectrum_color_at = 24'h00ff9f; 29: spectrum_color_at = 24'h00ffb7;
                30: spectrum_color_at = 24'h00ffcf; 31: spectrum_color_at = 24'h00ffe7;
                32: spectrum_color_at = 24'h00ffff; 33: spectrum_color_at = 24'h00e7ff;
                34: spectrum_color_at = 24'h00cfff; 35: spectrum_color_at = 24'h00b7ff;
                36: spectrum_color_at = 24'h009fff; 37: spectrum_color_at = 24'h0087ff;
                38: spectrum_color_at = 24'h0070ff; 39: spectrum_color_at = 24'h0058ff;
                40: spectrum_color_at = 24'h0040ff; 41: spectrum_color_at = 24'h0028ff;
                42: spectrum_color_at = 24'h0010ff; 43: spectrum_color_at = 24'h1808ff;
                44: spectrum_color_at = 24'h2000ff; 45: spectrum_color_at = 24'h3800ff;
                46: spectrum_color_at = 24'h5000ff; 47: spectrum_color_at = 24'h6800ff;
                48: spectrum_color_at = 24'h8000ff; 49: spectrum_color_at = 24'h9800ff;
                50: spectrum_color_at = 24'haf00ff; 51: spectrum_color_at = 24'hc700ff;
                52: spectrum_color_at = 24'hdf00ff; 53: spectrum_color_at = 24'hef00f7;
                54: spectrum_color_at = 24'hff00ef; 55: spectrum_color_at = 24'hff00d7;
                56: spectrum_color_at = 24'hff00bf; 57: spectrum_color_at = 24'hff00a7;
                58: spectrum_color_at = 24'hff008f; 59: spectrum_color_at = 24'hff0077;
                60: spectrum_color_at = 24'hff0060; 61: spectrum_color_at = 24'hff0048;
                62: spectrum_color_at = 24'hff0030; 63: spectrum_color_at = 24'hff0018;
                default: spectrum_color_at = 24'hff0000;
            endcase
        end
    end
endfunction

wire in_spectrum_area = (x >= X0) && (x < X0 + WIDTH) &&
                        (y >= Y0) && (y < Y0 + HEIGHT);
wire [5:0] bar_index = (x - X0) / BAR_WIDTH;
wire [7:0] bar_height = height_at(frame_heights, bar_index);
wire bar_pixel = in_spectrum_area && (bar_height != 0) &&
                 (y >= (Y0 + HEIGHT - bar_height));
wire [23:0] bar_color = spectrum_color_at(bar_index);
wire draw_spectrum = frame_enabled && ordinary_hidden && bar_pixel;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        pending_heights <= 512'd0;
        frame_heights <= 512'd0;
        pending_valid <= 1'b0;
        vs_prev <= 1'b0;
        de_prev <= 1'b0;
        x <= 11'd0;
        y <= 10'd0;
        enabled <= 1'b0;
        frame_enabled <= 1'b0;
        hs_out <= 1'b0;
        vs_out <= 1'b0;
        de_out <= 1'b0;
        rgb_out <= 24'd0;
    end else begin
        vs_prev <= vs;
        de_prev <= de;
        hs_out <= hs;
        vs_out <= vs;
        de_out <= de;
        rgb_out <= draw_spectrum ? bar_color : rgb_in;

        if (snapshot_valid) begin
            pending_heights <= snapshot_heights;
            pending_valid <= 1'b1;
        end

        if (s8_event && ordinary_scene)
            enabled <= ~enabled;
        else if (!ordinary_scene)
            enabled <= 1'b0;

        if (frame_boundary) begin
            if (pending_valid) begin
                frame_heights <= pending_heights;
                pending_valid <= 1'b0;
            end
            frame_enabled <= enabled;
            x <= 11'd0;
            y <= 10'd0;
        end else if (de) begin
            x <= x + 11'd1;
        end else if (de_prev) begin
            x <= 11'd0;
            if (y < FRAME_HEIGHT - 1)
                y <= y + 10'd1;
        end
    end
end

endmodule
