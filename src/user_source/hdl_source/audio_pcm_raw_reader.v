// Read a fixed-sector PCM package from the TF card.
//
// Package layout (all values little-endian):
//   sector AUDIO_START_SECTOR, bytes 0..3: "AUDP"
//   byte 4: version 1, byte 5: song count (currently 3)
//   bytes 8 + index*8: data start sector (u32), PCM byte length (u32)
//   song data: signed 16-bit little-endian stereo PCM, 48 kHz, no WAV header
//
// The host-side packer aligns every song to a sector boundary. This keeps the
// FPGA reader small and deterministic while the existing BMP scanner remains
// untouched below its 64 MiB scan limit.
module audio_pcm_raw_reader #(
    parameter [31:0] AUDIO_START_SECTOR = 32'd131072,
    parameter integer SONG_COUNT = 3
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,
    input  wire        sd_init_done,
    output reg         sd_sec_read,
    output reg [31:0]  sd_sec_read_addr,
    input  wire [7:0]  sd_sec_read_data,
    input  wire        sd_sec_read_data_valid,
    input  wire        sd_sec_read_end,
    output reg         fifo_wr_en,
    output reg [31:0]  fifo_wr_data,
    input  wire        fifo_full,
    input  wire        fifo_almost_full,
    output reg         stream_present
);

localparam ST_IDLE       = 4'd0;
localparam ST_HEADER     = 4'd1;
localparam ST_PARSE      = 4'd2;
localparam ST_DATA_REQ   = 4'd3;
localparam ST_DATA       = 4'd4;
localparam ST_NEXT_SONG  = 4'd5;
localparam ST_SILENT     = 4'd6;

reg [3:0] state;
reg [7:0] header [0:63];
reg [6:0] header_count;
reg [9:0] sector_count;
reg [1:0] song_idx;
reg [31:0] song_start_sector;
reg [31:0] song_remaining;
reg [3:0] remaining_zero_bytes;
wire song_empty=&remaining_zero_bytes;
function [3:0] zero_bytes;
 input [31:0] value;
 begin zero_bytes={value[31:24]==0,value[23:16]==0,value[15:8]==0,value[7:0]==0};end
endfunction
reg [31:0] current_sector;
reg [1:0] sample_byte_idx;
reg [31:0] sample_shift;
reg req_seen_data;
reg package_valid;
reg header_valid_q;

// All six signature bytes settle long before the 512-byte sector ends.
// Keep the wide comparison out of the song-load register enables.
always @(posedge clk or posedge rst) begin
    if (rst) header_valid_q <= 1'b0;
    else header_valid_q <= (header[0] == "A" && header[1] == "U" &&
                            header[2] == "D" && header[3] == "P" &&
                            header[4] == 8'd1 && header[5] >= SONG_COUNT);
end

wire [31:0] entry0_start = {header[11],header[10],header[9],header[8]};
wire [31:0] entry0_len   = {header[15],header[14],header[13],header[12]};
wire [31:0] entry1_start = {header[19],header[18],header[17],header[16]};
wire [31:0] entry1_len   = {header[23],header[22],header[21],header[20]};
wire [31:0] entry2_start = {header[27],header[26],header[25],header[24]};
wire [31:0] entry2_len   = {header[31],header[30],header[29],header[28]};

// Song index and header are stable for the duration of each song. Select
// the following descriptor early, removing its mux from the counter load path.
reg [31:0] next_song_start_q,next_song_len_q;
reg [3:0] next_song_zero_q;
always @(posedge clk or posedge rst) begin
 if(rst)begin next_song_start_q<=0;next_song_len_q<=0;next_song_zero_q<=15;end
 else if(song_idx==SONG_COUNT-1)begin
  next_song_start_q<=AUDIO_START_SECTOR+entry0_start;
  next_song_len_q<=entry0_len;next_song_zero_q<=zero_bytes(entry0_len);
 end else if(song_idx==0)begin
  next_song_start_q<=AUDIO_START_SECTOR+entry1_start;
  next_song_len_q<=entry1_len;next_song_zero_q<=zero_bytes(entry1_len);
 end else begin
  next_song_start_q<=AUDIO_START_SECTOR+entry2_start;
  next_song_len_q<=entry2_len;next_song_zero_q<=zero_bytes(entry2_len);
 end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state             <= ST_IDLE;
        sd_sec_read       <= 1'b0;
        sd_sec_read_addr  <= 32'd0;
        fifo_wr_en        <= 1'b0;
        fifo_wr_data      <= 32'd0;
        stream_present    <= 1'b0;
        header_count      <= 7'd0;
        sector_count      <= 10'd0;
        song_idx          <= 2'd0;
        song_start_sector <= 32'd0;
        song_remaining    <= 32'd0;
        remaining_zero_bytes <= 4'b1111;
        current_sector    <= 32'd0;
        sample_byte_idx   <= 2'd0;
        sample_shift      <= 32'd0;
        req_seen_data     <= 1'b0;
        package_valid     <= 1'b0;
    end else begin
        fifo_wr_en <= 1'b0;

        if (!enable || !sd_init_done) begin
            state            <= ST_IDLE;
            sd_sec_read      <= 1'b0;
            stream_present   <= 1'b0;
            package_valid    <= 1'b0;
            header_count     <= 7'd0;
            song_idx         <= 2'd0;
            req_seen_data    <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    stream_present   <= 1'b0;
                    header_count     <= 7'd0;
                    sd_sec_read_addr <= AUDIO_START_SECTOR;
                    sd_sec_read      <= 1'b1;
                    req_seen_data    <= 1'b0;
                    state            <= ST_HEADER;
                end

                ST_HEADER: begin
                    if (sd_sec_read_data_valid) begin
                        if (!req_seen_data) begin
                            sd_sec_read   <= 1'b0;
                            req_seen_data <= 1'b1;
                        end
                        if (header_count < 7'd64) begin
                            header[header_count] <= sd_sec_read_data;
                            header_count <= header_count + 7'd1;
                        end
                    end
                    if (sd_sec_read_end) begin
                        sd_sec_read <= 1'b0;
                        req_seen_data <= 1'b0;
                        state <= ST_PARSE;
                    end
                end

                ST_PARSE: begin
                    package_valid <= header_valid_q;
                    song_idx <= 2'd0;
                    if (header_valid_q) begin
                        song_start_sector <= AUDIO_START_SECTOR + entry0_start;
                        song_remaining    <= entry0_len;
                        remaining_zero_bytes <= zero_bytes(entry0_len);
                        current_sector    <= AUDIO_START_SECTOR + entry0_start;
                        sample_byte_idx   <= 2'd0;
                        state             <= ST_DATA_REQ;
                        stream_present    <= 1'b1;
                    end else begin
                        state <= ST_SILENT;
                    end
                end

                ST_DATA_REQ: begin
                    if (song_empty) begin
                        state <= ST_NEXT_SONG;
                    end else if (fifo_almost_full) begin
                        // A 512-byte sector contains at most 128 stereo
                        // frames. Wait until there is room for that whole
                        // sector before starting another SD transaction.
                        state <= ST_DATA_REQ;
                    end else begin
                        sd_sec_read_addr <= current_sector;
                        sd_sec_read      <= 1'b1;
                        req_seen_data    <= 1'b0;
                        sector_count     <= 10'd0;
                        state            <= ST_DATA;
                    end
                end

                ST_DATA: begin
                    if (sd_sec_read_data_valid) begin
                        if (!req_seen_data) begin
                            sd_sec_read   <= 1'b0;
                            req_seen_data <= 1'b1;
                        end
                        if (!song_empty) begin
                            song_remaining <= song_remaining - 32'd1;
                            // Track byte-zero flags with the decrement. Each comparator is
                            // eight bits; borrow predicates use registered zero flags.
                            remaining_zero_bytes[0] <= song_remaining[7:0]==1;
                            remaining_zero_bytes[1] <= remaining_zero_bytes[0] ? song_remaining[15:8]==1 : remaining_zero_bytes[1];
                            remaining_zero_bytes[2] <= (&remaining_zero_bytes[1:0]) ? song_remaining[23:16]==1 : remaining_zero_bytes[2];
                            remaining_zero_bytes[3] <= (&remaining_zero_bytes[2:0]) ? song_remaining[31:24]==1 : remaining_zero_bytes[3];
                            sector_count <= sector_count + 10'd1;
                            case (sample_byte_idx)
                                2'd0: begin sample_shift[7:0]   <= sd_sec_read_data; sample_byte_idx <= 2'd1; end
                                2'd1: begin sample_shift[15:8]  <= sd_sec_read_data; sample_byte_idx <= 2'd2; end
                                2'd2: begin sample_shift[23:16] <= sd_sec_read_data; sample_byte_idx <= 2'd3; end
                                default: begin
                                    sample_shift[31:24] <= sd_sec_read_data;
                                    sample_byte_idx <= 2'd0;
                                    if (!fifo_full)
                                        fifo_wr_en <= 1'b1;
                                    fifo_wr_data <= {sd_sec_read_data, sample_shift[23:0]};
                                end
                            endcase
                        end
                    end
                    if (sd_sec_read_end) begin
                        sd_sec_read  <= 1'b0;
                        req_seen_data <= 1'b0;
                        if (song_empty)
                            state <= ST_NEXT_SONG;
                        else begin
                            current_sector <= current_sector + 32'd1;
                            state <= ST_DATA_REQ;
                        end
                    end
                end

                ST_NEXT_SONG: begin
                    song_idx <= (song_idx==SONG_COUNT-1) ? 2'd0 : song_idx+1'b1;
                    song_start_sector <= next_song_start_q;
                    song_remaining <= next_song_len_q;
                    remaining_zero_bytes <= next_song_zero_q;
                    current_sector <= next_song_start_q;
                    sample_byte_idx <= 2'd0;
                    state <= ST_DATA_REQ;
                end

                ST_SILENT: begin
                    sd_sec_read <= 1'b0;
                    stream_present <= 1'b0;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
end

endmodule
