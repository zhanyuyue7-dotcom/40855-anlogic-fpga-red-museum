`timescale 1ns/1ps
// ============================================================================
// boot_video_stream -- power-on animation producer (SD/card clock domain)
//
// Reads the raw-sector animation block written by tools/pack_boot_video.py and
// turns it into full 640x480 frames in SDRAM through the existing
// frame_read_write write port. Nothing else in the display path changes.
//
// Data flow per pixel:
//
//   TF bytes (RGB565, bottom-up rows)
//     -> 1 KB sector FIFO          (decouples the atomic 512 B sector burst)
//     -> 320-entry line buffer     (source row)
//     -> 2 x horizontal repeat + 2 x vertical repeat   = 2x2 upscale
//     -> {R8,G8,B8,8'h00} word     (same packing as the BMP path)
//
// Row order: frame_fifo_write runs with WRITE_V_FLIP=1, mapping input row i to
// SDRAM row (FRAME_HEIGHT-1-i). The packer already stores rows bottom-up, so
// this block emits them in file order and the on-screen result is upright. Do
// not "fix" the ordering here without changing the packer too.
//
// Buffer contract (two frames, SDRAM indices 2 and 3):
//   - a frame is written into whichever boot buffer the consumer has released
//   - ready_toggle[b] flips once the SDRAM write of that frame has finished
//   - consumed_toggle[b] arrives from boot_video_play once the pixel side has
//     moved off buffer b; the buffer is reusable when the two toggles match
// Every crossing is a single bit, so plain two-flop synchronizers are legal.
//
// This block owns the TF bus from reset until the last frame is in SDRAM, then
// it releases it permanently so the ordinary BMP slideshow can initialize in
// parallel with the final frame still being on screen.
// ============================================================================
module boot_video_stream_ref #(
    parameter integer  SRC_W            = 320,
    parameter integer  SRC_H            = 240,
    parameter [31:0]   START_SECTOR     = 32'd262144,
    parameter [20:0]   BUF_ADDR0        = 21'd614400,
    parameter [20:0]   BUF_ADDR1        = 21'd921600,
    parameter integer  INIT_TIMEOUT     = 300_000_000,  // 3 s @ 100 MHz
    parameter integer  STALL_TIMEOUT    = 20_000_000    // 0.2 s @ 100 MHz
)(
    input               clk,
    input               rst,

    // dedicated TF master; the top level muxes these onto the board pins
    output              SD_nCS,
    output              SD_DCLK,
    output              SD_MOSI,
    input               SD_MISO,
    input               sd_init_done,
    output reg          sd_sec_read,
    output reg [31:0]   sd_sec_read_addr,
    input      [7:0]    sd_sec_read_data,
    input               sd_sec_read_data_valid,
    input               sd_sec_read_end,

    // frame buffer write port (shared with sd_card_bmp through a top-level mux)
    output reg          write_req,
    input               write_req_ack,
    output reg          write_en,
    output reg [31:0]   write_data,
    input               write_finish_toggle,   // frame_write_toggle_mem
    output reg [1:0]    write_addr_index,

    // hand-off
    output reg          owns_sd,
    output reg [1:0]    ready_toggle,
    input      [1:0]    consumed_toggle,
    output reg          stream_done,
    output reg          stream_abort,
    output reg [15:0]   frames_written,
    output reg [3:0]    status_code
);

localparam integer FRAME_BYTES        = SRC_W * SRC_H * 2;
localparam integer SECTORS_PER_FRAME  = FRAME_BYTES / 512;
localparam integer HDR_BYTES          = 20;

localparam [3:0] S_WAIT_INIT = 4'd1,
                 S_HDR       = 4'd2,
                 S_ACQ       = 4'd3,
                 S_WREQ      = 4'd4,
                 S_WREL      = 4'd5,
                 S_DATA      = 4'd6,
                 S_FIN       = 4'd7,
                 S_DONE      = 4'd8,
                 S_ABORT     = 4'd9;

localparam [1:0] R_RECV   = 2'd0,
                 R_EMIT_A = 2'd1,
                 R_EMIT_B = 2'd2;

reg [3:0]  state;
reg [31:0] init_cnt;
reg [31:0] stall_cnt;
reg [31:0] acq_cnt;      // separate, much longer: the display paces this wait

// ---------------------------------------------------------------- CDC inputs
(* async_reg = "true" *) reg [1:0] cons_s0, cons_s1;
wire [1:0] cons_sync = cons_s1;

(* async_reg = "true" *) reg [1:0] ack_s0, ack_s1;
wire ack_sync = ack_s1;

reg [2:0] wfin_sync;
wire wfin_pulse = wfin_sync[2] ^ wfin_sync[1];

always @(posedge clk or posedge rst) begin
    if (rst) begin
        cons_s0 <= 2'b00; cons_s1 <= 2'b00;
        ack_s0  <= 1'b0;  ack_s1  <= 1'b0;
        wfin_sync <= 3'b000;
    end else begin
        cons_s0 <= consumed_toggle;  cons_s1 <= cons_s0;
        ack_s0  <= write_req_ack;    ack_s1  <= ack_s0;
        wfin_sync <= {wfin_sync[1:0], write_finish_toggle};
    end
end

// ------------------------------------------------------------- sector FIFO
// The card delivers a 512-byte sector as one uninterrupted burst, so the byte
// stream cannot be paused at a row boundary. Buffer it and drain at will.
reg  [7:0]  sfifo [0:1023];
reg  [10:0] sf_wptr, sf_rptr;
wire [10:0] sf_count = sf_wptr - sf_rptr;
wire        sf_room  = (sf_count <= 11'd512);
wire        sf_have  = (sf_count != 11'd0);
wire [7:0]  sf_dout  = sfifo[sf_rptr[9:0]];

// header capture (first sector of the block)
reg [7:0]  hdr [0:HDR_BYTES-1];
reg [4:0]  hdr_cnt;

wire [15:0] hdr_src_w       = {hdr[5],  hdr[4]};
wire [15:0] hdr_src_h       = {hdr[7],  hdr[6]};
wire [15:0] hdr_frame_count = {hdr[13], hdr[12]};
wire [31:0] hdr_frame_bytes = {hdr[19], hdr[18], hdr[17], hdr[16]};

// Decided from the captured bytes, which are settled long before the sector
// end pulse, so this can stay combinational and needs no extra register.
wire hdr_valid = (hdr[0] == 8'h42) && (hdr[1] == 8'h56) &&
                 (hdr[2] == 8'h50) && (hdr[3] == 8'h31) &&
                 (hdr_src_w == SRC_W) && (hdr_src_h == SRC_H) &&
                 (hdr_frame_bytes == FRAME_BYTES) &&
                 (hdr_frame_count != 16'd0);

// --------------------------------------------------------------- row engine
reg  [15:0] linebuf [0:SRC_W-1];
reg  [8:0]  row_y;
reg  [8:0]  px_x;
reg  [1:0]  row_state;
reg         byte_phase;
reg  [7:0]  byte_low;
reg  [1:0]  emit_ph;
reg  [15:0] px_hold;

// RGB565 -> RGB888 by replicating the most significant bits of each field,
// so 0 maps to 0x00 and the field maximum maps to 0xFF (full scale preserved).
wire [15:0] px565 = px_hold;
wire [7:0]  r8 = {px565[15:11], px565[15:13]};
wire [7:0]  g8 = {px565[10:5],  px565[10:9]};
wire [7:0]  b8 = {px565[4:0],   px565[4:2]};

// ------------------------------------------------------------------ handshake
reg        wr_sel;
reg [15:0] frame_target;

// A boot buffer is reusable once the producer toggle matches the consumer's.
wire [1:0] buf_free = ~(ready_toggle ^ cons_sync);

// ------------------------------------------------------------- sector pump
// One request at a time, held until the sector completes, exactly like
// bmp_read.v. The next request waits for FIFO room.
wire pump_en = (state == S_HDR) || (state == S_DATA);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        sd_sec_read      <= 1'b0;
        sd_sec_read_addr <= START_SECTOR;
    end else if (!pump_en) begin
        sd_sec_read <= 1'b0;
    end else if (sd_sec_read) begin
        if (sd_sec_read_end) begin
            sd_sec_read      <= 1'b0;
            sd_sec_read_addr <= sd_sec_read_addr + 32'd1;
        end
    end else if (sf_room) begin
        sd_sec_read <= 1'b1;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        sf_wptr <= 11'd0;
    end else if (sd_sec_read_data_valid) begin
        if (state != S_HDR) begin
            sfifo[sf_wptr[9:0]] <= sd_sec_read_data;
            sf_wptr <= sf_wptr + 11'd1;
        end
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        hdr_cnt <= 5'd0;
    end else if (state == S_HDR && sd_sec_read_data_valid) begin
        if (hdr_cnt < HDR_BYTES)
            hdr[hdr_cnt] <= sd_sec_read_data;
        if (hdr_cnt != 5'd31)
            hdr_cnt <= hdr_cnt + 5'd1;
    end
end

// ------------------------------------------------------------ main sequencer
always @(posedge clk or posedge rst) begin
    if (rst) begin
        state            <= S_WAIT_INIT;
        init_cnt         <= 32'd0;
        stall_cnt        <= 32'd0;
        acq_cnt          <= 32'd0;
        write_req        <= 1'b0;
        write_en         <= 1'b0;
        write_data       <= 32'd0;
        write_addr_index <= 2'd2;
        owns_sd          <= 1'b1;
        ready_toggle     <= 2'b00;
        stream_done      <= 1'b0;
        stream_abort     <= 1'b0;
        frames_written   <= 16'd0;
        status_code      <= 4'd0;
        row_y            <= 9'd0;
        px_x             <= 9'd0;
        row_state        <= R_RECV;
        byte_phase       <= 1'b0;
        byte_low         <= 8'd0;
        emit_ph          <= 2'd0;
        px_hold          <= 16'd0;
        wr_sel           <= 1'b0;
        frame_target     <= 16'd0;
        // The producer block owns sf_wptr; this sequencer owns the read side of
        // the sector FIFO, so resetting sf_rptr here keeps a single driver.
        sf_rptr          <= 11'd0;
    end else begin
        // retry / stall watchdog
        if (sd_sec_read_data_valid || sd_sec_read_end)
            stall_cnt <= 32'd0;
        else if (stall_cnt != 32'hFFFF_FFFF)
            stall_cnt <= stall_cnt + 32'd1;

        // Waiting for the display to release a buffer is paced by 60 Hz VS, so
        // it needs its own much longer budget than a byte-level stall.
        if (state == S_ACQ)
            acq_cnt <= acq_cnt + 32'd1;
        else
            acq_cnt <= 32'd0;

        case (state)
        // ------------------------------------------------------- wait for card
        S_WAIT_INIT: begin
            status_code <= 4'd1;
            if (sd_init_done && !init_cnt[31]) begin
                // The sector pump below owns sd_sec_read_addr and already
                // restarts it at START_SECTOR on reset; driving it here as well
                // made the net a multi-driver error at elaboration.
                state       <= S_HDR;
            end else if (init_cnt != 32'hFFFF_FFFF) begin
                init_cnt <= init_cnt + 32'd1;
                if (init_cnt >= INIT_TIMEOUT) begin
                    state        <= S_ABORT;
                    stream_abort <= 1'b1;
                    owns_sd      <= 1'b0;
                    status_code  <= 4'd8;
                end
            end else begin
                state        <= S_ABORT;
                stream_abort <= 1'b1;
                owns_sd      <= 1'b0;
                status_code  <= 4'd8;
            end
        end

        // --------------------------------------------------------- read header
        S_HDR: begin
            status_code <= 4'd2;
            if (stall_cnt >= STALL_TIMEOUT) begin
                state        <= S_ABORT;
                stream_abort <= 1'b1;
                owns_sd      <= 1'b0;
                status_code  <= 4'd9;
            end else if (sd_sec_read_end) begin
                if (hdr_valid) begin
                    frame_target <= hdr_frame_count;
                    state        <= S_ACQ;
                end else begin
                    // Card present but no animation block: silently hand back.
                    state        <= S_ABORT;
                    stream_abort <= 1'b1;
                    owns_sd      <= 1'b0;
                    status_code  <= 4'd7;
                end
            end
        end

        // ----------------------------------------------------- pick a buffer
        S_ACQ: begin
            status_code <= 4'd3;
            if (frames_written >= frame_target) begin
                state       <= S_DONE;
                stream_done <= 1'b1;
                owns_sd     <= 1'b0;
                status_code <= 4'd4;
            end else if (buf_free[wr_sel]) begin
                write_addr_index <= wr_sel ? 2'd3 : 2'd2;
                write_req        <= 1'b1;
                row_y            <= 9'd0;
                px_x             <= 9'd0;
                row_state        <= R_RECV;
                byte_phase       <= 1'b0;
                emit_ph          <= 2'd0;
                state            <= S_WREQ;
            end else if (acq_cnt >= INIT_TIMEOUT) begin
                // consumer never released a buffer: give up rather than stall
                state        <= S_ABORT;
                stream_abort <= 1'b1;
                owns_sd      <= 1'b0;
                status_code  <= 4'd11;
            end
        end

        // ---------------------------------------------- frame write handshake
        S_WREQ: begin
            status_code <= 4'd4;
            if (ack_sync) begin
                write_req <= 1'b0;
                state     <= S_WREL;
            end
        end

        S_WREL: begin
            // frame_fifo_write clears its write FIFO during ack; data must not
            // stream until the request is fully released.
            status_code <= 4'd4;
            if (!ack_sync) begin
                state     <= S_DATA;
                stall_cnt <= 32'd0;
            end
        end

        // ------------------------------------------------------ stream pixels
        S_DATA: begin
            status_code <= 4'd5;
            if (stall_cnt >= STALL_TIMEOUT) begin
                state        <= S_ABORT;
                stream_abort <= 1'b1;
                owns_sd      <= 1'b0;
                status_code  <= 4'd10;
            end else begin
                write_en <= 1'b0;
                case (row_state)
                // ------------------------------------------ source row in
                R_RECV: begin
                    if (sf_have) begin
                        sf_rptr <= sf_rptr + 11'd1;
                        if (!byte_phase) begin
                            byte_low   <= sf_dout;
                            byte_phase <= 1'b1;
                        end else begin
                            byte_phase        <= 1'b0;
                            linebuf[px_x[8:0]] <= {sf_dout, byte_low};
                            px_x              <= px_x + 9'd1;
                            if (px_x == SRC_W-1) begin
                                px_x      <= 9'd0;
                                row_state <= R_EMIT_A;
                                emit_ph   <= 2'd0;
                            end
                        end
                    end
                end
                // ------------------------------------ emit the row, pass A
                R_EMIT_A: begin
                    case (emit_ph)
                    2'd0: begin
                        px_hold <= linebuf[px_x[8:0]];
                        emit_ph <= 2'd1;
                    end
                    2'd1: begin
                        write_en   <= 1'b1;
                        write_data <= {r8, g8, b8, 8'h00};
                        emit_ph    <= 2'd2;
                    end
                    default: begin
                        write_en   <= 1'b1;
                        write_data <= {r8, g8, b8, 8'h00};
                        emit_ph    <= 2'd0;
                        px_x       <= px_x + 9'd1;
                        if (px_x == SRC_W-1) begin
                            px_x      <= 9'd0;
                            row_state <= R_EMIT_B;
                        end
                    end
                    endcase
                end
                // ------------------------------------ emit the row, pass B
                R_EMIT_B: begin
                    case (emit_ph)
                    2'd0: begin
                        px_hold <= linebuf[px_x[8:0]];
                        emit_ph <= 2'd1;
                    end
                    2'd1: begin
                        write_en   <= 1'b1;
                        write_data <= {r8, g8, b8, 8'h00};
                        emit_ph    <= 2'd2;
                    end
                    default: begin
                        write_en   <= 1'b1;
                        write_data <= {r8, g8, b8, 8'h00};
                        emit_ph    <= 2'd0;
                        px_x       <= px_x + 9'd1;
                        if (px_x == SRC_W-1) begin
                            px_x <= 9'd0;
                            if (row_y == SRC_H-1) begin
                                row_state <= R_RECV;
                                state     <= S_FIN;
                            end else begin
                                row_y     <= row_y + 9'd1;
                                row_state <= R_RECV;
                            end
                        end
                    end
                    endcase
                end
                default: row_state <= R_RECV;
                endcase
            end
        end

        // ------------------------------------------- wait for SDRAM write done
        S_FIN: begin
            status_code <= 4'd5;
            write_en    <= 1'b0;
            if (wfin_pulse) begin
                ready_toggle[wr_sel] <= ~ready_toggle[wr_sel];
                frames_written       <= frames_written + 16'd1;
                wr_sel               <= ~wr_sel;
                state                <= S_ACQ;
            end else if (stall_cnt >= STALL_TIMEOUT) begin
                state        <= S_ABORT;
                stream_abort <= 1'b1;
                owns_sd      <= 1'b0;
                status_code  <= 4'd12;
            end
        end

        // ------------------------------------------------------ terminal states
        S_DONE: begin
            status_code <= 4'd6;
            write_en    <= 1'b0;
            owns_sd     <= 1'b0;
        end

        S_ABORT: begin
            status_code <= (status_code == 4'd0) ? 4'd15 : status_code;
            write_en    <= 1'b0;
            owns_sd     <= 1'b0;
            stream_abort <= 1'b1;
        end

        default: state <= S_ABORT;
        endcase
    end
end

// ------------------------------------------------------------------- TF pins
sd_card_top boot_sd_card (
    .clk                    (clk),
    .rst                    (rst),
    .SD_nCS                 (SD_nCS),
    .SD_DCLK                (SD_DCLK),
    .SD_MOSI                (SD_MOSI),
    .SD_MISO                (SD_MISO),
    .sd_init_done           (sd_init_done),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .sd_sec_write           (1'b0),
    .sd_sec_write_addr      (32'd0),
    .sd_sec_write_data      (),
    .sd_sec_write_data_req  (),
    .sd_sec_write_end       ()
);

endmodule
