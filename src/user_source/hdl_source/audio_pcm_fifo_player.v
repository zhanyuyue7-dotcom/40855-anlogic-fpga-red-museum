// Consume packed 16-bit stereo PCM frames at an exact average 48 kHz rate.
// The HDMI transmitter consumes 24-bit samples, so the 16-bit source is
// sign-extended by shifting it eight places.
module audio_pcm_fifo_player #(
    parameter integer VIDEO_CLK_HZ = 25_000_000,
    parameter integer SAMPLE_RATE_HZ = 48_000
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        fifo_empty,
    input  wire [31:0] fifo_data,
    output reg         fifo_rd_en,
    output reg         audio_valid,
    output reg [23:0]  audio_left,
    output reg [23:0]  audio_right,
    output reg         stream_started
);

reg [31:0] phase_acc;
wire [31:0] phase_sum = phase_acc + SAMPLE_RATE_HZ;
wire sample_tick = (phase_sum >= VIDEO_CLK_HZ);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        phase_acc      <= 32'd0;
        fifo_rd_en     <= 1'b0;
        audio_valid    <= 1'b0;
        audio_left     <= 24'd0;
        audio_right    <= 24'd0;
        stream_started <= 1'b0;
    end else begin
        fifo_rd_en  <= 1'b0;
        audio_valid <= 1'b0;
        if (sample_tick)
            phase_acc <= phase_sum - VIDEO_CLK_HZ;
        else
            phase_acc <= phase_sum;

        if (sample_tick && !fifo_empty) begin
            fifo_rd_en  <= 1'b1;
            audio_valid <= 1'b1;
            audio_left  <= {fifo_data[31:16], 8'd0};
            audio_right <= {fifo_data[15:0], 8'd0};
            stream_started <= 1'b1;
        end
    end
end

endmodule
