// Two-flop synchronizer for the 2 ms network event levels produced by
// w5500_virtual_inputs (50 MHz domain) into the 25 MHz video domain.
//
// A one-cycle network pulse would be invisible to a slower destination clock,
// so the source stretches every command to EVENT_CYCLES (2 ms) and this module
// recovers a single-cycle rise in the destination domain. Only rising edges are
// used, which makes a duplicated packet inside the same 2 ms window a no-op.
module net_event_sync(
    input  wire       dst_clk,
    input  wire       dst_rst,
    input  wire       src_notice,
    input  wire       src_emergency,
    input  wire       src_clear,
    output wire       event_pulse,
    output wire [1:0] event_scene,
    output wire       clear_pulse
);
    (* async_reg = "true" *) reg [2:0] sync0, sync1, sync2;

    always @(posedge dst_clk or posedge dst_rst) begin
        if (dst_rst) begin
            sync0 <= 3'b000;
            sync1 <= 3'b000;
            sync2 <= 3'b000;
        end else begin
            sync0 <= {src_emergency, src_clear, src_notice};
            sync1 <= sync0;
            sync2 <= sync1;
        end
    end

    wire [2:0] rise = sync1 & ~sync2;

    assign clear_pulse = rise[1];
    assign event_pulse = rise[2] | rise[0];
    assign event_scene = rise[2] ? 2'd2 : 2'd1;
endmodule
