// Standalone SP3 display/control wrapper.
//
// The top level supplies a debounced persistent mode level. This wrapper turns
// either S4 transition into one event, then lets spectrum_overlay perform the
// frame-safe enable/snapshot commit. Scene alerts and UI fade still have
// priority in the pixel path.
module spectrum_sp3_display #(
    parameter integer FRAME_WIDTH = 640,
    parameter integer FRAME_HEIGHT = 480,
    parameter integer X0 = 32,
    parameter integer Y0 = 280,
    parameter integer WIDTH = 576,
    parameter integer HEIGHT = 160,
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
    input  wire         s8_pressed,
    input  wire         snapshot_valid,
    input  wire [511:0] snapshot_heights,
    output wire         hs_out,
    output wire         vs_out,
    output wire         de_out,
    output wire [23:0]  rgb_out,
    output wire         enabled,
    output wire         s8_event
);
    reg s8_prev;
    assign s8_event = s8_pressed ^ s8_prev;

    always @(posedge clk or posedge rst) begin
        if (rst)
            s8_prev <= 1'b0;
        else
            s8_prev <= s8_pressed;
    end

    spectrum_overlay #(
        .FRAME_WIDTH(FRAME_WIDTH), .FRAME_HEIGHT(FRAME_HEIGHT),
        .X0(X0), .Y0(Y0), .WIDTH(WIDTH), .HEIGHT(HEIGHT)
        ,.COLOR_MODE(COLOR_MODE)
    ) u_overlay (
        .clk(clk), .rst(rst), .hs(hs), .vs(vs), .de(de), .rgb_in(rgb_in),
        .scene_id(scene_id), .ui_fade_level(ui_fade_level),
        .s8_event(s8_event), .snapshot_valid(snapshot_valid),
        .snapshot_heights(snapshot_heights), .hs_out(hs_out), .vs_out(vs_out),
        .de_out(de_out), .rgb_out(rgb_out), .enabled(enabled)
    );
endmodule
