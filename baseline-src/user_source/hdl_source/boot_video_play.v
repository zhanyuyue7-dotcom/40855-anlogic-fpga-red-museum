`timescale 1ns/1ps
// ============================================================================
// boot_video_play -- power-on animation consumer (pixel clock domain)
//
// Owns the frame hand-off and the one-shot hand-over to the normal UI.
//
// Frame pacing needs no frame-rate counter: the producer can only fill a buffer
// every ~57 ms of SPI time, and the pixel side may only switch buffers on a VS
// edge, so playback is bounded above by 60 fps and in practice runs at the card
// rate. FRAME_VS_HOLD adds a lower bound so that a fast card cannot race ahead
// into a visible stutter.
//
// Buffer credit (two boot buffers, SDRAM indices 2 and 3):
//   ready_toggle[b]    producer -> here, flips after the SDRAM write completes
//   consumed_toggle[b] here -> producer, flips once the pixel side leaves b
// A buffer holds a fresh frame when the two toggles differ.
//
// One-shot behaviour: boot_active rises out of reset and never comes back.
// It falls at a VS edge once the card side has finished AND the ordinary BMP
// path has committed its first image, so there is no black gap between the
// animation and the normal UI. HANDOVER_MAX_VS is a hard cap in case the card
// holds no BMP images at all.
// ============================================================================
module boot_video_play #(
    parameter integer FRAME_VS_HOLD   = 4,    // 60 Hz / 4 = 15 fps floor
    parameter integer HANDOVER_MAX_VS = 600   // 10 s cap after the stream ends
)(
    input               clk,          // video_clk, 25 MHz
    input               rst,
    input               vs,
    input               de,

    input               bmp_display_valid,  // pixel_sd_monitor[56]
    input      [1:0]    ready_toggle,       // from boot_video_stream
    output reg [1:0]    consumed_toggle,    // back to boot_video_stream
    input               stream_done,        // level, safe single-bit CDC
    input               stream_abort,

    output reg          read_sel,       // 0 -> SDRAM index 2, 1 -> index 3
    output reg          boot_active,    // 1 while the animation owns the screen
    output reg          boot_has_frame, // at least one frame is being displayed
    output reg [15:0]   frames_shown,
    output reg [15:0]   underrun_count  // VS edges where the producer was late
);

// ------------------------------------------------------------------ CDC
(* async_reg = "true" *) reg [1:0] rd_s0, rd_s1;
(* async_reg = "true" *) reg       done_s0, done_s1;
(* async_reg = "true" *) reg       abort_s0, abort_s1;

wire [1:0] ready_sync = rd_s1;
wire       done_sync  = done_s1;
wire       abort_sync = abort_s1;

// ------------------------------------------------------------------ VS edge
reg  vs_d;
wire vs_rise = vs & ~vs_d;

wire [1:0] pend  = ready_sync ^ consumed_toggle;
wire       other = ~read_sel;

reg [7:0]  hold_cnt;
reg [9:0]  handover_cnt;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        rd_s0 <= 2'b00; rd_s1 <= 2'b00;
        done_s0 <= 1'b0; done_s1 <= 1'b0;
        abort_s0 <= 1'b0; abort_s1 <= 1'b0;
        vs_d <= 1'b0;
        read_sel         <= 1'b0;
        boot_active      <= 1'b1;
        boot_has_frame   <= 1'b0;
        consumed_toggle  <= 2'b00;
        hold_cnt         <= 8'd0;
        handover_cnt     <= 10'd0;
        frames_shown     <= 16'd0;
        underrun_count   <= 16'd0;
    end else begin
        rd_s0    <= ready_toggle;
        rd_s1    <= rd_s0;
        done_s0  <= stream_done;
        done_s1  <= done_s0;
        abort_s0 <= stream_abort;
        abort_s1 <= abort_s0;
        vs_d     <= vs;

        if (vs_rise) begin
            // ---- one-shot hand-over -------------------------------------
            // Let the animation finish on screen, then swap to the slideshow
            // exactly when the slideshow has something to show.
            if (boot_active && (done_sync || abort_sync)) begin
                if (handover_cnt != 10'h3FF)
                    handover_cnt <= handover_cnt + 10'd1;

                if (bmp_display_valid || handover_cnt >= HANDOVER_MAX_VS)
                    boot_active <= 1'b0;
            end

            // ---- acquire the very first frame ---------------------------
            if (boot_active && !boot_has_frame) begin
                if (pend[0]) begin
                    read_sel       <= 1'b0;
                    boot_has_frame <= 1'b1;
                    hold_cnt       <= 8'd0;
                end else if (pend[1]) begin
                    read_sel       <= 1'b1;
                    boot_has_frame <= 1'b1;
                    hold_cnt       <= 8'd0;
                end
            end
            // ---- normal double-buffer rotation --------------------------
            else if (boot_active && boot_has_frame) begin
                if (hold_cnt != 8'hFF)
                    hold_cnt <= hold_cnt + 8'd1;

                if (pend[other] && (hold_cnt >= FRAME_VS_HOLD-1)) begin
                    // Release the buffer we are leaving; the producer may refill.
                    consumed_toggle[read_sel] <= ~consumed_toggle[read_sel];
                    read_sel     <= other;
                    hold_cnt     <= 8'd0;
                    frames_shown <= frames_shown + 16'd1;
                end else if (!done_sync && !abort_sync && (pend == 2'b00) &&
                             (hold_cnt >= FRAME_VS_HOLD)) begin
                    // Producer has not delivered the next frame in time.
                    if (underrun_count != 16'hFFFF)
                        underrun_count <= underrun_count + 16'd1;
                end
            end
        end
    end
end

endmodule
