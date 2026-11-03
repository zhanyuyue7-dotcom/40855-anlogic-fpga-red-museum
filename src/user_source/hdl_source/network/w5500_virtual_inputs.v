// Converts the remaining network control events into short active-low
// compatibility levels. Scene notice/emergency/clear are handled by the
// frame-domain event bridge in top_tf_hdmi_audio and do not pass here.
//
// An emergency request is not a single key: on the board it is SW1 (emergency
// priority) held down while KEY3 is pressed. The network path therefore raises
// a virtual SW1 first, waits EMERGENCY_ARM_CYCLES so the 25 MHz input debouncer
// can settle on "emergency", and only then presses the virtual KEY3. That keeps
// the scene arbiter on the exact same sampled inputs as a local operator.
module w5500_virtual_inputs #(
    parameter integer HOLD_CYCLES = 100_000,
    parameter integer EMERGENCY_ARM_CYCLES = 1_500_000
)(
    input  wire clk,
    input  wire rst,
    input  wire cmd_next,
    input  wire cmd_auto_toggle,
    input  wire cmd_notice,
    input  wire cmd_emergency,
    input  wire cmd_clear,
    input  wire cmd_brightness_up,
    input  wire cmd_brightness_down,
    output wire key_next_n,
    output wire key_auto_n,
    output wire key_event_n,
    output wire sw_emergency,
    output wire sw_clear,
    output wire key_brightness_up_n,
    output wire key_brightness_down_n
);
    localparam integer COUNT_BITS = HOLD_CYCLES <= 1 ? 1 : $clog2(HOLD_CYCLES + 1);
    // Virtual SW1 stays high until the emergency key press has been debounced
    // and released, so the arbiter samples the emergency scene, not "notice".
    localparam integer EMERGENCY_SWITCH_CYCLES = EMERGENCY_ARM_CYCLES + (2 * HOLD_CYCLES);
    localparam integer EMERGENCY_BITS = EMERGENCY_SWITCH_CYCLES <= 1 ? 1 : $clog2(EMERGENCY_SWITCH_CYCLES + 1);
    reg [COUNT_BITS-1:0] next_count, auto_count, notice_count, clear_count, up_count, down_count;
    reg [COUNT_BITS-1:0] emergency_key_count;
    reg [EMERGENCY_BITS-1:0] emergency_switch_count, emergency_arm_count;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            next_count <= 0; auto_count <= 0; notice_count <= 0;
            clear_count <= 0; up_count <= 0; down_count <= 0;
            emergency_key_count <= 0;
            emergency_switch_count <= 0; emergency_arm_count <= 0;
        end else begin
            if (cmd_next) next_count <= HOLD_CYCLES;
            else if (next_count != 0) next_count <= next_count - 1'b1;
            if (cmd_auto_toggle) auto_count <= HOLD_CYCLES;
            else if (auto_count != 0) auto_count <= auto_count - 1'b1;
            if (cmd_notice) notice_count <= HOLD_CYCLES;
            else if (notice_count != 0) notice_count <= notice_count - 1'b1;
            if (cmd_clear) clear_count <= HOLD_CYCLES;
            else if (clear_count != 0) clear_count <= clear_count - 1'b1;
            if (cmd_brightness_up) up_count <= HOLD_CYCLES;
            else if (up_count != 0) up_count <= up_count - 1'b1;
            if (cmd_brightness_down) down_count <= HOLD_CYCLES;
            else if (down_count != 0) down_count <= down_count - 1'b1;

            if (cmd_emergency) begin
                emergency_switch_count <= EMERGENCY_SWITCH_CYCLES;
                emergency_arm_count    <= EMERGENCY_ARM_CYCLES;
                emergency_key_count    <= 0;
            end else begin
                if (emergency_arm_count != 0) begin
                    emergency_arm_count <= emergency_arm_count - 1'b1;
                    if (emergency_arm_count == 1)
                        emergency_key_count <= HOLD_CYCLES;
                end else if (emergency_key_count != 0)
                    emergency_key_count <= emergency_key_count - 1'b1;
                if (emergency_switch_count != 0)
                    emergency_switch_count <= emergency_switch_count - 1'b1;
            end
        end
    end

    assign key_next_n            = (next_count == 0);
    assign key_auto_n            = (auto_count == 0);
    assign key_event_n           = (notice_count == 0) && (emergency_key_count == 0);
    assign sw_emergency          = (emergency_switch_count != 0);
    assign sw_clear              = (clear_count != 0);
    assign key_brightness_up_n   = (up_count == 0);
    assign key_brightness_down_n = (down_count == 0);
endmodule
