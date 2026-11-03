// Dedicated S5/S6 brightness inputs; synchronized into the SD/control domain.
// No adjustment mode and no slideshow key multiplexing. One step per press.
module display_parameter_ctrl #(
    parameter integer DEBOUNCE_CYCLES = 2_000_000
)(
    input wire clk, rst,
    input wire sw_audio_enable,
    input wire key_down_n, key_up_n,
    input wire network_down_event, network_up_event,
    output wire adjust_mode,
    output reg [1:0] brightness_level,
    output wire audio_enable
);
    wire audio_level, down_level, up_level, down_press, up_press;
    display_input_debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES), .RESET_LEVEL(1'b0)) u_audio_enable(
        .clk(clk), .rst(rst), .input_async(sw_audio_enable),
        .level(audio_level), .rise(), .fall());
    display_input_debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES), .RESET_LEVEL(1'b1)) u_down(
        .clk(clk), .rst(rst), .input_async(key_down_n),
        .level(down_level), .rise(), .fall(down_press));
    display_input_debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES), .RESET_LEVEL(1'b1)) u_up(
        .clk(clk), .rst(rst), .input_async(key_up_n),
        .level(up_level), .rise(), .fall(up_press));
    // Preserve OSD/UART metadata interface: always normal operation.
    assign adjust_mode = 1'b0;
    assign audio_enable = audio_level;
    always @(posedge clk or posedge rst) begin
        if (rst) brightness_level <= 2'd3;
        else begin
            case ({network_up_event | up_press, network_down_event | down_press})
                2'b01: if (network_down_event || (up_level && brightness_level != 2'd0))
                    brightness_level <= brightness_level - 1'b1;
                2'b10: if (network_up_event || (down_level && brightness_level != 2'd3))
                    brightness_level <= brightness_level + 1'b1;
                default: ;
            endcase
        end
    end
endmodule

module display_input_debounce #(
    parameter integer STABLE_CYCLES = 2_000_000,
    parameter RESET_LEVEL = 1'b0
)(
    input  wire clk,
    input  wire rst,
    input  wire input_async,
    output reg  level,
    output reg  rise,
    output reg  fall
);
    localparam integer COUNT_BITS = STABLE_CYCLES <= 1 ? 1 : $clog2(STABLE_CYCLES);
    (* async_reg = "true" *) reg sync0, sync1;
    reg [COUNT_BITS-1:0] count;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sync0 <= RESET_LEVEL;
            sync1 <= RESET_LEVEL;
            level <= RESET_LEVEL;
            count <= 0;
            rise <= 1'b0;
            fall <= 1'b0;
        end else begin
            sync0 <= input_async;
            sync1 <= sync0;
            rise <= 1'b0;
            fall <= 1'b0;
            if (sync1 == level) begin
                count <= 0;
            end else if (STABLE_CYCLES <= 1 || count == STABLE_CYCLES - 1) begin
                level <= sync1;
                count <= 0;
                rise <= sync1;
                fall <= !sync1;
            end else begin
                count <= count + 1'b1;
            end
        end
    end
endmodule
