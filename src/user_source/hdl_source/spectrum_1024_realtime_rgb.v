// ============================================================================
// 1024-point real-time RGB spectrum showcase
// ============================================================================
// This is the deliberately self-contained spectrum deliverable entry point.
// It keeps the audio analysis and video visualization in one named module so
// the feature is easy to review and selectively upload to a larger design.
//
// Data path:
//   48 kHz stereo samples -> spectrum_fft_1024 (双缓冲、Hann、FFT、64 bands)
//                         -> 64x8-bit frame-safe snapshot
//                         -> spectrum_sp3_display (S8/UI gating + RGB ROM)
//                         -> RGB/DE/HS/VS video
//
// The wrapper is standalone. It does not modify the production top-level or
// its .al compile list. COLOR_MODE=1 selects the fixed 64-entry rainbow RGB
// table; the legacy overlay remains available with COLOR_MODE=0.
// ============================================================================
module spectrum_1024_realtime_rgb #(
    parameter integer FRAME_WIDTH = 640,
    parameter integer FRAME_HEIGHT = 480,
    parameter integer X0 = 32,
    parameter integer Y0 = 280,
    parameter integer WIDTH = 576,
    parameter integer HEIGHT = 160
)(
    input  wire clk,
    input  wire rst,
    input  wire sample_valid,
    input  wire signed [15:0] sample_left,
    input  wire signed [15:0] sample_right,
    output wire sample_ready,
    output wire spectrum_snapshot_valid,
    output wire [511:0] spectrum_snapshot_heights,
    output wire spectrum_busy,
    input  wire hs,
    input  wire vs,
    input  wire de,
    input  wire [23:0] rgb_in,
    input  wire [1:0] scene_id,
    input  wire [5:0] ui_fade_level,
    input  wire s8_pressed,
    output wire hs_out,
    output wire vs_out,
    output wire de_out,
    output wire [23:0] rgb_out,
    output wire spectrum_enabled,
    output wire s8_event
);
    spectrum_fft_1024 u_fft_1024 (
        .clk(clk), .rst(rst),
        .sample_valid(sample_valid),
        .sample_left(sample_left), .sample_right(sample_right),
        .sample_ready(sample_ready),
        .snapshot_valid(spectrum_snapshot_valid),
        .snapshot_heights(spectrum_snapshot_heights),
        .busy(spectrum_busy)
    );

    spectrum_sp3_display #(
        .FRAME_WIDTH(FRAME_WIDTH), .FRAME_HEIGHT(FRAME_HEIGHT),
        .X0(X0), .Y0(Y0), .WIDTH(WIDTH), .HEIGHT(HEIGHT),
        .COLOR_MODE(1)
    ) u_rgb_display (
        .clk(clk), .rst(rst),
        .hs(hs), .vs(vs), .de(de), .rgb_in(rgb_in),
        .scene_id(scene_id), .ui_fade_level(ui_fade_level),
        .s8_pressed(s8_pressed),
        .snapshot_valid(spectrum_snapshot_valid),
        .snapshot_heights(spectrum_snapshot_heights),
        .hs_out(hs_out), .vs_out(vs_out), .de_out(de_out),
        .rgb_out(rgb_out), .enabled(spectrum_enabled),
        .s8_event(s8_event)
    );
endmodule
