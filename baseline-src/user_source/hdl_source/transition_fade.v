// Low-cost frame-boundary fade for ordinary image changes.
// Smooth mode uses 33 levels implemented with constant shifts and additions.
// SMOOTH=0 preserves the original four-level diagnostic mode.
module transition_fade #(
    parameter integer FRAME_HOLD = 1,
    parameter integer LEVEL_HOLD = 1,
    parameter integer SMOOTH = 1,
    parameter integer ENABLE = 1
)(
    input wire        clk,
    input wire        rst,
    input wire        vs,
    input wire        de,
    input wire [23:0] rgb_in,
    input wire        start_toggle,
    input wire        commit_toggle,
    input wire        abort_transition, // pixel-domain committed emergency level
    output wire [23:0] rgb_out,
    output wire [5:0]  fade_level,
    output wire        transition_active
);
    localparam [1:0] PHASE_IDLE = 2'd0;
    localparam [1:0] PHASE_OUT  = 2'd1;
    localparam [1:0] PHASE_HOLD = 2'd2;
    localparam [1:0] PHASE_IN   = 2'd3;
    localparam [5:0] FULL_LEVEL = SMOOTH ? 6'd32 : 6'd3;

    reg vs_prev;
    reg [1:0] phase;
    reg [5:0] level;
    reg [15:0] hold_frames;
    (* async_reg = "true" *) reg [1:0] start_sync;
    (* async_reg = "true" *) reg [1:0] commit_sync;
    reg start_seen;
    reg commit_seen;
    reg commit_pending;

    wire frame_boundary = vs_prev && !vs && !de;
    wire start_pulse = start_sync[1] ^ start_seen;
    wire commit_pulse = commit_sync[1] ^ commit_seen;

    assign fade_level = ENABLE ? level : FULL_LEVEL;
    assign transition_active = ENABLE && (phase != PHASE_IDLE);

    function [7:0] scale_channel;
        input [7:0] channel;
        input [5:0] gain;
        reg [12:0] sum;
        integer bit_index;
        begin
            sum = 13'd0;
            for (bit_index=0; bit_index<5; bit_index=bit_index+1)
                if (gain[bit_index]) sum = sum + ({5'd0,channel} << bit_index);
            scale_channel = gain[5] ? channel : sum[12:5];
        end
    endfunction

    function [23:0] scale_rgb;
        input [23:0] rgb;
        input [5:0] scale;
        reg [7:0] r;
        reg [7:0] g;
        reg [7:0] b;
        begin
            if (SMOOTH) begin
                scale_rgb = {scale_channel(rgb[23:16],scale),
                             scale_channel(rgb[15:8],scale),
                             scale_channel(rgb[7:0],scale)};
            end else case (scale)
                2'd0: scale_rgb = 24'h000000;
                2'd1: begin
                    r = rgb[23:16] >> 2;
                    g = rgb[15:8]  >> 2;
                    b = rgb[7:0]   >> 2;
                    scale_rgb = {r, g, b};
                end
                2'd2: begin
                    r = rgb[23:16] >> 1;
                    g = rgb[15:8]  >> 1;
                    b = rgb[7:0]   >> 1;
                    scale_rgb = {r, g, b};
                end
                default: scale_rgb = rgb;
            endcase
        end
    endfunction

    assign rgb_out = !ENABLE ? rgb_in : (!de ? 24'd0 : scale_rgb(rgb_in, fade_level));

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            vs_prev <= 1'b0;
            phase <= PHASE_IDLE;
            level <= FULL_LEVEL;
            hold_frames <= 16'd0;
            start_sync <= 2'b00;
            commit_sync <= 2'b00;
            start_seen <= 1'b0;
            commit_seen <= 1'b0;
            commit_pending <= 1'b0;
        end else begin
            vs_prev <= vs;
            start_sync <= {start_sync[0], start_toggle};
            commit_sync <= {commit_sync[0], commit_toggle};

            if (!ENABLE) begin
                phase <= PHASE_IDLE;
                level <= FULL_LEVEL;
                hold_frames <= 16'd0;
                start_seen <= start_sync[1];
                commit_seen <= commit_sync[1];
                commit_pending <= 1'b0;
            end else if (abort_transition) begin
                // Emergency presentation owns the display. Drop any
                // in-flight ordinary-image fade so it cannot resume after the
                // event scene returns to the background.
                phase <= PHASE_IDLE;
                level <= FULL_LEVEL;
                hold_frames <= 16'd0;
                commit_pending <= 1'b0;
                start_seen <= start_sync[1];
                commit_seen <= commit_sync[1];
            end else begin
                if (start_pulse) begin
                    start_seen <= start_sync[1];
                    phase <= PHASE_OUT;
                    // Preserve current brightness when another load starts
                    // during fade-in; brightness changes only at frame edges.
                    hold_frames <= (LEVEL_HOLD > 0) ? LEVEL_HOLD - 1 : 0;
                    commit_pending <= 1'b0;
                end
                if (commit_pulse) begin
                    commit_seen <= commit_sync[1];
                    if (phase != PHASE_IDLE) begin
                        commit_pending <= 1'b1;
                        if (phase == PHASE_HOLD) begin
                            level <= 2'd0;
                            hold_frames <= FRAME_HOLD;
                        end
                    end
                end

                if (frame_boundary && !start_pulse && !commit_pulse) begin
                    case (phase)
                        PHASE_OUT: begin
                            if (hold_frames != 0) begin
                                hold_frames <= hold_frames - 1'b1;
                            end else if (level <= 2'd1) begin
                                level <= 2'd0;
                                phase <= PHASE_HOLD;
                                hold_frames <= commit_pending ? FRAME_HOLD : 16'd0;
                            end else begin
                                level <= level - 1'b1;
                                hold_frames <= (LEVEL_HOLD > 0) ? LEVEL_HOLD - 1 : 0;
                            end
                        end
                        PHASE_HOLD: begin
                            if (commit_pending && (hold_frames != 0)) begin
                                hold_frames <= hold_frames - 1'b1;
                            end else if (commit_pending) begin
                                phase <= PHASE_IN;
                                level <= 2'd1;
                                hold_frames <= (LEVEL_HOLD > 0) ? LEVEL_HOLD - 1 : 0;
                                commit_pending <= 1'b0;
                            end
                        end
                        PHASE_IN: begin
                            if (hold_frames != 0) begin
                                hold_frames <= hold_frames - 1'b1;
                            end else if (level >= FULL_LEVEL - 1'b1) begin
                                level <= FULL_LEVEL;
                                phase <= PHASE_IDLE;
                            end else begin
                                level <= level + 1'b1;
                                hold_frames <= (LEVEL_HOLD > 0) ? LEVEL_HOLD - 1 : 0;
                            end
                        end
                        default: begin
                            phase <= PHASE_IDLE;
                            level <= FULL_LEVEL;
                        end
                    endcase
                end
            end
        end
    end
endmodule

// Freeze the reader's buffer throughout fade-out. The SD controller retains
// its existing source/write completion contract and next-image scheduling.
module transition_buffer_select(
    input wire clk, rst,
    input wire [1:0] disp_buf_idx,
    input wire transition_active,
    input wire black,
    output reg [1:0] read_buf_idx
);
    (* async_reg = "true" *) reg [1:0] buf_meta, buf_sync;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            buf_meta <= 0;
            buf_sync <= 0;
            read_buf_idx <= 0;
        end else begin
            buf_meta <= disp_buf_idx;
            buf_sync <= buf_meta;
            if (!transition_active || black) read_buf_idx <= buf_sync;
        end
    end
endmodule

// Release the black hold only after the video reader has accepted a frame
// read using the newly committed display buffer. The SD-side commit toggle
// and buffer index cross into the video clock domain independently.
module transition_commit_guard(
    input  wire       clk,
    input  wire       rst,
    input  wire       commit_toggle,
    input  wire [1:0] disp_buf_idx,
    input  wire       read_req_ack,
    input  wire       vs,
    input  wire       de,
    output reg        ready_toggle
);
    (* async_reg = "true" *) reg [1:0] commit_sync;
    (* async_reg = "true" *) reg [1:0] buf_idx_sync_ff1;
    (* async_reg = "true" *) reg [1:0] buf_idx_sync_ff2;
    reg commit_seen;
    reg [1:0] buf_idx_seen;
    (* async_reg = "true" *) reg [1:0] read_ack_sync;
    reg read_ack_prev;
    reg commit_pending;
    reg vs_prev, read_armed;
    reg [1:0] candidate_idx;

    wire commit_pulse = commit_sync[1] ^ commit_seen;
    wire read_ack_pulse = read_ack_sync[1] && !read_ack_prev;
    wire frame_boundary = vs_prev && !vs && !de;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            commit_sync   <= 2'b00;
            buf_idx_sync_ff1 <= 2'b00;
            buf_idx_sync_ff2 <= 2'b00;
            commit_seen   <= 1'b0;
            buf_idx_seen  <= 2'b00;
            read_ack_sync <= 2'b00;
            read_ack_prev <= 1'b0;
            commit_pending <= 1'b0;
            ready_toggle  <= 1'b0;
            vs_prev <= 1'b0;
            read_armed <= 1'b0;
            candidate_idx <= 0;
        end else begin
            vs_prev <= vs;
            commit_sync   <= {commit_sync[0], commit_toggle};
            buf_idx_sync_ff1 <= disp_buf_idx;
            buf_idx_sync_ff2 <= buf_idx_sync_ff1;
            read_ack_sync <= {read_ack_sync[0], read_req_ack};
            read_ack_prev <= read_ack_sync[1];

            if (commit_pulse) begin
                commit_seen    <= commit_sync[1];
                commit_pending <= 1'b1;
                read_armed <= 1'b0;
            end

            // Require the selected index to be stable before a new frame
            // request, then accept only a subsequent synchronized ACK.
            // An ACK already in flight at the buffer switch is insufficient.
            if (candidate_idx != buf_idx_sync_ff2) begin
                candidate_idx <= buf_idx_sync_ff2;
                read_armed <= 1'b0;
            end else if (commit_pending && !commit_pulse && frame_boundary &&
                         (buf_idx_sync_ff2 != buf_idx_seen)) begin
                read_armed <= 1'b1;
            end
            if (commit_pending && !commit_pulse && read_armed && read_ack_pulse &&
                (candidate_idx == buf_idx_sync_ff2) &&
                (buf_idx_sync_ff2 != buf_idx_seen)) begin
                buf_idx_seen   <= buf_idx_sync_ff2;
                commit_pending <= 1'b0;
                ready_toggle   <= ~ready_toggle;
                read_armed <= 1'b0;
            end
        end
    end
endmodule
