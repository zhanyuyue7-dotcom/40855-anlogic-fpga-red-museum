// Independent input synchronizers/debouncers; no dependence on TF/SDRAM state.
module scene_debounce #(
    parameter integer STABLE_CYCLES = 500000,
    parameter RESET_LEVEL = 1'b1
)(
    input wire clk, rst, input_async,
    output reg level, rise, fall
);
    localparam integer COUNT_BITS = STABLE_CYCLES <= 1 ? 1 : $clog2(STABLE_CYCLES);
    (* async_reg = "true" *) reg sync0, sync1;
    reg [COUNT_BITS-1:0] count;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sync0 <= RESET_LEVEL; sync1 <= RESET_LEVEL;
            level <= RESET_LEVEL; count <= 0; rise <= 0; fall <= 0;
        end else begin
            sync0 <= input_async;
            sync1 <= sync0;
            rise <= 0; fall <= 0;
            if (sync1 == level) count <= 0;
            else if (count == STABLE_CYCLES - 1) begin
                level <= sync1; count <= 0;
                rise <= sync1; fall <= !sync1;
            end else count <= count + 1'b1;
        end
    end
endmodule

module scene_inputs #(
    parameter integer DEBOUNCE_CYCLES = 500000
)(
    input wire clk, rst, key_event_n, sw_emergency, sw_clear,
    input wire network_event_valid,
    input wire [1:0] network_event_scene,
    input wire network_clear_request,
    output wire event_trigger,
    output wire [1:0] event_scene,
    output wire clear_request
);
    wire emergency_level;
    wire local_event_trigger;
    wire local_clear_request;
    wire [1:0] local_event_scene;
    scene_debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) u_event_key(
        .clk(clk), .rst(rst), .input_async(key_event_n),
        .level(), .rise(), .fall(local_event_trigger)
    );
    scene_debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES), .RESET_LEVEL(1'b0)) u_priority_switch(
        .clk(clk), .rst(rst), .input_async(sw_emergency),
        .level(emergency_level), .rise(), .fall()
    );
    scene_debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES), .RESET_LEVEL(1'b0)) u_clear_switch(
        .clk(clk), .rst(rst), .input_async(sw_clear),
        .level(), .rise(local_clear_request), .fall()
    );
    assign local_event_scene = emergency_level ? 2'd2 : 2'd1;
    // Network scene commands are already validated events and do not need the
    // 20 ms mechanical debounce applied to local keys.
    assign event_trigger = network_event_valid | local_event_trigger;
    assign event_scene = network_event_valid ? network_event_scene : local_event_scene;
    assign clear_request = network_clear_request | local_clear_request;
endmodule
