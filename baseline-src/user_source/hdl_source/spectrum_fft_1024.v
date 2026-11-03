// Standalone fixed-point 1024-point stereo FFT feasibility core.
//
// The capture side uses two raw stereo windows so the next 48 kHz window can
// be collected while the previous window is being transformed. The compute
// side time-multiplexes one radix-2 FFT over left and right channels and emits
// planned 64x8-bit snapshot interface. It remains standalone until the
// audio-domain integration stage adds the final source handshake.
module spectrum_fft_1024 #(
    parameter integer FFT_SIZE = 1024,
    parameter integer BAND_COUNT = 64,
    parameter integer HEIGHT_MAX = 160
)(
    input  wire         clk,
    input  wire         rst,
    input  wire         sample_valid,
    input  wire signed [15:0] sample_left,
    input  wire signed [15:0] sample_right,
    output wire         sample_ready,
    output reg          snapshot_valid,
    output reg [511:0]  snapshot_heights,
    output wire         busy
);

localparam [3:0] ST_IDLE       = 4'd0;
localparam [3:0] ST_PREP_LEFT  = 4'd1;
localparam [3:0] ST_FFT_LEFT   = 4'd2;
localparam [3:0] ST_SCAN_LEFT  = 4'd3;
localparam [3:0] ST_PREP_RIGHT = 4'd4;
localparam [3:0] ST_FFT_RIGHT  = 4'd5;
localparam [3:0] ST_SCAN_RIGHT = 4'd6;
localparam [3:0] ST_FIND_MAX   = 4'd7;
localparam [3:0] ST_WRITE_HEIGHT = 4'd8;
localparam [3:0] ST_START_HEIGHT = 4'd9;
localparam [3:0] ST_DIVIDE      = 4'd10;

reg [3:0] state;
reg [2:0] butterfly_phase;
reg signed [27:0] butterfly_a_re;
reg signed [27:0] butterfly_a_im;
reg signed [27:0] butterfly_b_re;
reg signed [27:0] butterfly_b_im;
reg prep_phase;
reg scan_phase;
reg [31:0] prep_stereo_sample_reg;
reg signed [27:0] scan_re_reg;
reg signed [27:0] scan_im_reg;
reg [9:0] capture_index;
// Fixed standalone contract: 25 MHz / 48 kHz gives 520/521 clocks per sample.
// If 521 consecutive clocks have no accepted sample, discard only the partial
// capture window. Never join samples across an audio interruption. Completed
// buffers and the compute FSM are independent and remain valid.
reg [9:0] capture_idle_cycles;
// Per-window signed sums support deterministic DC removal before the Hann
// multiply. A 26-bit accumulator covers 1024 * signed 16-bit PCM.
reg signed [25:0] capture_sum_left0, capture_sum_right0;
reg signed [25:0] capture_sum_left1, capture_sum_right1;
reg [9:0] prep_index;
reg [3:0] fft_stage;
reg [8:0] butterfly_index;
reg [9:0] bin_index;
reg [5:0] max_index;
reg [5:0] height_index;
reg signed [63:0] max_power;
reg signed [63:0] band_power [0:63];
reg [63:0] divide_numerator;
reg [63:0] divide_denominator;
reg [63:0] divide_remainder;
reg [63:0] divide_quotient;
reg [6:0] divide_count;

reg capture_buffer;
reg compute_buffer;
reg full_buffer0, full_buffer1;
reg compute_busy0, compute_busy1;

wire [31:0] raw_stereo0_read_data;
wire [31:0] raw_stereo1_read_data;
wire signed [27:0] work_re_read_data;
wire signed [27:0] work_im_read_data;

wire capture_buffer_blocked = capture_buffer ?
    (full_buffer1 || compute_busy1) : (full_buffer0 || compute_busy0);
assign sample_ready = !capture_buffer_blocked;
assign busy = (state != ST_IDLE) || full_buffer0 || full_buffer1 ||
              compute_busy0 || compute_busy1;

wire [9:0] hann_addr = prep_index;
wire signed [15:0] hann_value;
spectrum_hann_rom u_hann(.addr(hann_addr), .value(hann_value));

function automatic [9:0] bit_reverse_10;
    input [9:0] value;
    integer b;
    begin
        for (b=0; b<10; b=b+1)
            bit_reverse_10[b] = value[9-b];
    end
endfunction

wire [9:0] prep_reverse_addr = bit_reverse_10(prep_index);
wire [31:0] prep_stereo_sample = compute_buffer ?
    raw_stereo1_read_data : raw_stereo0_read_data;
wire signed [15:0] prep_left_sample = prep_stereo_sample[31:16];
wire signed [15:0] prep_right_sample = prep_stereo_sample[15:0];
wire signed [15:0] prep_selected_sample =
    (state == ST_PREP_RIGHT) ? prep_right_sample : prep_left_sample;
wire signed [25:0] prep_left_sum = compute_buffer ? capture_sum_left1 : capture_sum_left0;
wire signed [25:0] prep_right_sum = compute_buffer ? capture_sum_right1 : capture_sum_right0;
wire signed [15:0] prep_left_mean = prep_left_sum >>> 10;
wire signed [15:0] prep_right_mean = prep_right_sum >>> 10;
wire signed [15:0] prep_selected_mean =
    (state == ST_PREP_RIGHT) ? prep_right_mean : prep_left_mean;
wire signed [16:0] prep_centered_sample =
    $signed({prep_selected_sample[15], prep_selected_sample}) -
    $signed({prep_selected_mean[15], prep_selected_mean});

// Radix-2 DIT addresses without runtime division/modulo.  For a stage with
// half_size=2^fft_stage, offset is the low fft_stage bits, addr_a is
// 2*butterfly_index-offset, and addr_b is addr_a+half_size.
wire [9:0] half_size = 10'd1 << fft_stage;
wire [9:0] offset_index = {1'b0, butterfly_index} & (half_size - 10'd1);
wire [9:0] addr_a_index = ({1'b0, butterfly_index} << 1) - offset_index;
wire [9:0] addr_b_index = addr_a_index + half_size;
wire [8:0] twiddle_addr = offset_index << (9 - fft_stage);

wire signed [15:0] twiddle_cos;
wire signed [15:0] twiddle_sin;
spectrum_twiddle_rom u_twiddle(
    .addr(twiddle_addr), .cos_value(twiddle_cos), .sin_value(twiddle_sin)
);

wire signed [43:0] product_re_cos = butterfly_b_re * twiddle_cos;
wire signed [43:0] product_im_sin = butterfly_b_im * twiddle_sin;
wire signed [43:0] product_im_cos = butterfly_b_im * twiddle_cos;
wire signed [43:0] product_re_sin = butterfly_b_re * twiddle_sin;
wire signed [44:0] rotated_re = product_re_cos - product_im_sin;
wire signed [44:0] rotated_im = product_im_cos + product_re_sin;
wire signed [29:0] rotated_re_q15 = rotated_re >>> 15;
wire signed [29:0] rotated_im_q15 = rotated_im >>> 15;

wire raw_read_en = ((state == ST_PREP_LEFT) || (state == ST_PREP_RIGHT)) && !prep_phase;
wire raw0_read_en = raw_read_en && !compute_buffer;
wire raw1_read_en = raw_read_en && compute_buffer;
wire raw0_write_en = sample_valid && sample_ready && !capture_buffer;
wire raw1_write_en = sample_valid && sample_ready && capture_buffer;

spectrum_sync_ram_1024 #(.DATA_WIDTH(32)) u_raw_stereo0 (
    .clk(clk), .write_en(raw0_write_en), .write_addr(capture_index),
    .write_data({sample_left, sample_right}), .read_en(raw0_read_en),
    .read_addr(prep_index), .read_data(raw_stereo0_read_data)
);
spectrum_sync_ram_1024 #(.DATA_WIDTH(32)) u_raw_stereo1 (
    .clk(clk), .write_en(raw1_write_en), .write_addr(capture_index),
    .write_data({sample_left, sample_right}), .read_en(raw1_read_en),
    .read_addr(prep_index), .read_data(raw_stereo1_read_data)
);

wire work_fft_state = (state == ST_FFT_LEFT) || (state == ST_FFT_RIGHT);
wire work_scan_state = (state == ST_SCAN_LEFT) || (state == ST_SCAN_RIGHT);
wire work_read_en = (work_fft_state && ((butterfly_phase == 3'd0) ||
                                         (butterfly_phase == 3'd1))) ||
                    (work_scan_state && !scan_phase);
wire [9:0] work_read_addr = work_fft_state ?
    ((butterfly_phase == 3'd0) ? addr_a_index : addr_b_index) : bin_index;
wire work_write_en = (((state == ST_PREP_LEFT) || (state == ST_PREP_RIGHT)) && prep_phase) ||
                     (work_fft_state && ((butterfly_phase == 3'd3) ||
                                          (butterfly_phase == 3'd4)));
wire [9:0] work_write_addr =
    ((state == ST_PREP_LEFT) || (state == ST_PREP_RIGHT)) ? prep_reverse_addr :
    ((butterfly_phase == 3'd3) ? addr_a_index : addr_b_index);
// Keep the full centered-sample x Q15 product before scaling. The centered
// sample is 17 bits because subtracting a signed mean can exceed 16 bits.
wire signed [32:0] prep_window_product = prep_centered_sample * hann_value;
wire signed [27:0] prep_work_re_data = prep_window_product >>> 15;
wire signed [27:0] prep_work_im_data = 28'sd0;
wire signed [27:0] fft_work_re_a = butterfly_a_re + rotated_re_q15;
wire signed [27:0] fft_work_im_a = butterfly_a_im + rotated_im_q15;
wire signed [27:0] fft_work_re_b = butterfly_a_re - rotated_re_q15;
wire signed [27:0] fft_work_im_b = butterfly_a_im - rotated_im_q15;
wire signed [27:0] work_write_re_data =
    (((state == ST_PREP_LEFT) || (state == ST_PREP_RIGHT)) ? prep_work_re_data :
     ((butterfly_phase == 3'd3) ? fft_work_re_a : fft_work_re_b));
wire signed [27:0] work_write_im_data =
    (((state == ST_PREP_LEFT) || (state == ST_PREP_RIGHT)) ? prep_work_im_data :
     ((butterfly_phase == 3'd3) ? fft_work_im_a : fft_work_im_b));

spectrum_sync_ram_1024 #(.DATA_WIDTH(28)) u_work_re (
    .clk(clk), .write_en(work_write_en), .write_addr(work_write_addr),
    .write_data(work_write_re_data), .read_en(work_read_en),
    .read_addr(work_read_addr), .read_data(work_re_read_data)
);
spectrum_sync_ram_1024 #(.DATA_WIDTH(28)) u_work_im (
    .clk(clk), .write_en(work_write_en), .write_addr(work_write_addr),
    .write_data(work_write_im_data), .read_en(work_read_en),
    .read_addr(work_read_addr), .read_data(work_im_read_data)
);

wire signed [55:0] scan_re_square = $signed(work_re_read_data) * $signed(work_re_read_data);
wire signed [55:0] scan_im_square = $signed(work_im_read_data) * $signed(work_im_read_data);
wire signed [56:0] scan_power = scan_re_square + scan_im_square;
integer scan_band_index;
// Eight FFT bins per visual band: 1..512 -> 64 bands at 375 Hz/band.
always @* scan_band_index = (bin_index - 1) >> 3;

// Scale by HEIGHT_MAX=160 without a DSP multiplier.  The quotient itself is
// calculated by a 64-cycle restoring divider in ST_DIVIDE, avoiding the
// several-hundred-nanosecond combinational division path.
wire [63:0] height_scaled =
    ($unsigned(band_power[height_index]) << 7) +
    ($unsigned(band_power[height_index]) << 5);
wire [64:0] divide_shifted_remainder =
    {divide_remainder, divide_numerator[63]};
wire divide_can_subtract =
    divide_shifted_remainder >= {1'b0, divide_denominator};
wire [64:0] divide_subtracted_remainder =
    divide_shifted_remainder - {1'b0, divide_denominator};
wire [63:0] divide_next_remainder = divide_can_subtract ?
    divide_subtracted_remainder[63:0] : divide_shifted_remainder[63:0];
wire [63:0] divide_next_quotient =
    {divide_quotient[62:0], divide_can_subtract};
wire [7:0] divide_height_value =
    (divide_next_quotient > HEIGHT_MAX) ? HEIGHT_MAX[7:0] :
    divide_next_quotient[7:0];

integer clear_index;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= ST_IDLE;
        butterfly_phase <= 3'd0;
        butterfly_a_re <= 28'sd0;
        butterfly_a_im <= 28'sd0;
        butterfly_b_re <= 28'sd0;
        butterfly_b_im <= 28'sd0;
        prep_phase <= 1'b0;
        scan_phase <= 1'b0;
        prep_stereo_sample_reg <= 32'd0;
        scan_re_reg <= 28'sd0;
        scan_im_reg <= 28'sd0;
        capture_index <= 10'd0;
        capture_idle_cycles <= 10'd0;
        capture_sum_left0 <= 26'sd0;
        capture_sum_right0 <= 26'sd0;
        capture_sum_left1 <= 26'sd0;
        capture_sum_right1 <= 26'sd0;
        prep_index <= 10'd0;
        fft_stage <= 4'd0;
        butterfly_index <= 9'd0;
        bin_index <= 10'd1;
        max_index <= 6'd0;
        height_index <= 6'd0;
        max_power <= 64'd0;
        divide_numerator <= 64'd0;
        divide_denominator <= 64'd0;
        divide_remainder <= 64'd0;
        divide_quotient <= 64'd0;
        divide_count <= 7'd0;
        snapshot_valid <= 1'b0;
        snapshot_heights <= 512'd0;
        capture_buffer <= 1'b0;
        compute_buffer <= 1'b0;
        full_buffer0 <= 1'b0;
        full_buffer1 <= 1'b0;
        compute_busy0 <= 1'b0;
        compute_busy1 <= 1'b0;
        for (clear_index=0; clear_index<64; clear_index=clear_index+1)
            band_power[clear_index] <= 64'd0;
    end else begin
        snapshot_valid <= 1'b0;

        // Continuous capture into whichever raw window is free. Once a
        // window is full, switch immediately to the other window; the
        // compute FSM consumes the completed window independently.
        if (sample_valid && sample_ready) begin
            capture_idle_cycles <= 10'd0;
            if (!capture_buffer) begin
                capture_sum_left0 <= capture_sum_left0 + $signed(sample_left);
                capture_sum_right0 <= capture_sum_right0 + $signed(sample_right);
                if (capture_index == 10'd1023) begin
                    capture_index <= 10'd0;
                    capture_buffer <= 1'b1;
                    full_buffer0 <= 1'b1;
                    capture_sum_left1 <= 26'sd0;
                    capture_sum_right1 <= 26'sd0;
                end else begin
                    capture_index <= capture_index + 10'd1;
                end
            end else begin
                capture_sum_left1 <= capture_sum_left1 + $signed(sample_left);
                capture_sum_right1 <= capture_sum_right1 + $signed(sample_right);
                if (capture_index == 10'd1023) begin
                    capture_index <= 10'd0;
                    capture_buffer <= 1'b0;
                    full_buffer1 <= 1'b1;
                    capture_sum_left0 <= 26'sd0;
                    capture_sum_right0 <= 26'sd0;
                end else begin
                    capture_index <= capture_index + 10'd1;
                end
            end
        end else if (capture_index != 10'd0) begin
            if (capture_idle_cycles == 10'd520) begin
                capture_index <= 10'd0;
                capture_idle_cycles <= 10'd0;
                if (!capture_buffer) begin
                    capture_sum_left0 <= 26'sd0;
                    capture_sum_right0 <= 26'sd0;
                end else begin
                    capture_sum_left1 <= 26'sd0;
                    capture_sum_right1 <= 26'sd0;
                end
            end else begin
                capture_idle_cycles <= capture_idle_cycles + 10'd1;
            end
        end else begin
            capture_idle_cycles <= 10'd0;
        end

        case (state)
            ST_IDLE: begin
                if (full_buffer0) begin
                    compute_buffer <= 1'b0;
                    full_buffer0 <= 1'b0;
                    compute_busy0 <= 1'b1;
                    prep_index <= 10'd0;
                    prep_phase <= 1'b0;
                    state <= ST_PREP_LEFT;
                end else if (full_buffer1) begin
                    compute_buffer <= 1'b1;
                    full_buffer1 <= 1'b0;
                    compute_busy1 <= 1'b1;
                    prep_index <= 10'd0;
                    prep_phase <= 1'b0;
                    state <= ST_PREP_LEFT;
                end
            end

            ST_PREP_LEFT: begin
                if (!prep_phase) begin
                    prep_phase <= 1'b1;
                end else begin
                    prep_phase <= 1'b0;
                    if (prep_index == 10'd1023) begin
                        fft_stage <= 4'd0;
                        butterfly_index <= 9'd0;
                        butterfly_phase <= 3'd0;
                        for (clear_index=0; clear_index<64; clear_index=clear_index+1)
                            band_power[clear_index] <= 64'd0;
                        state <= ST_FFT_LEFT;
                    end else begin
                        prep_index <= prep_index + 10'd1;
                    end
                end
            end

            ST_FFT_LEFT, ST_FFT_RIGHT: begin
                // Five phases keep each work RAM to one synchronous access per cycle:
                // issue A read, capture A/issue B read, capture B, write A, write B.
                case (butterfly_phase)
                    3'd0: begin
                        butterfly_phase <= 3'd1;
                    end
                    3'd1: begin
                        butterfly_a_re <= work_re_read_data;
                        butterfly_a_im <= work_im_read_data;
                        butterfly_phase <= 3'd2;
                    end
                    3'd2: begin
                        butterfly_b_re <= work_re_read_data;
                        butterfly_b_im <= work_im_read_data;
                        butterfly_phase <= 3'd3;
                    end
                    3'd3: begin
                        butterfly_phase <= 3'd4;
                    end
                    default: begin
                        butterfly_phase <= 3'd0;
                        if (butterfly_index == 9'd511) begin
                            butterfly_index <= 9'd0;
                            if (fft_stage == 4'd9) begin
                                bin_index <= 10'd1;
                                scan_phase <= 1'b0;
                                state <= (state == ST_FFT_LEFT) ? ST_SCAN_LEFT : ST_SCAN_RIGHT;
                            end else begin
                                fft_stage <= fft_stage + 4'd1;
                            end
                        end else begin
                            butterfly_index <= butterfly_index + 9'd1;
                        end
                    end
                endcase
            end

            ST_SCAN_LEFT, ST_SCAN_RIGHT: begin
                if (!scan_phase) begin
                    scan_phase <= 1'b1;
                end else begin
                    band_power[scan_band_index] <= band_power[scan_band_index] + scan_power;
                    scan_phase <= 1'b0;
                    if (bin_index == 10'd512) begin
                        if (state == ST_SCAN_LEFT) begin
                            prep_index <= 10'd0;
                            prep_phase <= 1'b0;
                            state <= ST_PREP_RIGHT;
                        end else begin
                            max_index <= 6'd0;
                            max_power <= 64'd0;
                            state <= ST_FIND_MAX;
                        end
                    end else begin
                        bin_index <= bin_index + 10'd1;
                    end
                end
            end

            ST_PREP_RIGHT: begin
                if (!prep_phase) begin
                    prep_phase <= 1'b1;
                end else begin
                    prep_phase <= 1'b0;
                    if (prep_index == 10'd1023) begin
                        fft_stage <= 4'd0;
                        butterfly_index <= 9'd0;
                        butterfly_phase <= 3'd0;
                        state <= ST_FFT_RIGHT;
                    end else begin
                        prep_index <= prep_index + 10'd1;
                    end
                end
            end

            ST_FIND_MAX: begin
                if (band_power[max_index] > max_power)
                    max_power <= band_power[max_index];
                if (max_index == 6'd63) begin
                    height_index <= 6'd0;
                    state <= ST_START_HEIGHT;
                end else begin
                    max_index <= max_index + 6'd1;
                end
            end

            ST_START_HEIGHT: begin
                if (max_power > 0) begin
                    divide_numerator <= height_scaled;
                    divide_denominator <= $unsigned(max_power);
                    divide_remainder <= 64'd0;
                    divide_quotient <= 64'd0;
                    divide_count <= 7'd0;
                    state <= ST_DIVIDE;
                end else begin
                    snapshot_heights[height_index*8 +: 8] <= 8'd0;
                    if (height_index == 6'd63) begin
                        snapshot_valid <= 1'b1;
                        if (compute_buffer)
                            compute_busy1 <= 1'b0;
                        else
                            compute_busy0 <= 1'b0;
                        state <= ST_IDLE;
                    end else begin
                        height_index <= height_index + 6'd1;
                    end
                end
            end

            ST_DIVIDE: begin
                divide_remainder <= divide_next_remainder;
                divide_quotient <= divide_next_quotient;
                divide_numerator <= {divide_numerator[62:0], 1'b0};
                if (divide_count == 7'd63) begin
                    snapshot_heights[height_index*8 +: 8] <= divide_height_value;
                    if (height_index == 6'd63) begin
                        snapshot_valid <= 1'b1;
                        if (compute_buffer)
                            compute_busy1 <= 1'b0;
                        else
                            compute_busy0 <= 1'b0;
                        state <= ST_IDLE;
                    end else begin
                        height_index <= height_index + 6'd1;
                        state <= ST_START_HEIGHT;
                    end
                end else begin
                    divide_count <= divide_count + 7'd1;
                end
            end

            default: state <= ST_IDLE;
        endcase
    end
end

endmodule
