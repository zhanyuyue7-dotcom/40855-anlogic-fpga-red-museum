// Synchronize the SD-domain recovery toggle into video clock and hold a
// bounded re-arm reset for transition state machines. The video timing source
// itself is intentionally not reset by this pulse.
module transition_recovery_reset(
    input  wire clk,
    input  wire rst,
    input  wire recovery_toggle,
    output wire recovery_reset
);
    (* async_reg = "true" *) reg [1:0] toggle_sync;
    reg [1:0] reset_hold;

    assign recovery_reset = |reset_hold;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            toggle_sync <= 2'b00;
            reset_hold <= 2'b00;
        end else begin
            toggle_sync <= {toggle_sync[0], recovery_toggle};
            if (toggle_sync[1] != toggle_sync[0])
                reset_hold <= 2'b11;
            else if (reset_hold != 0)
                reset_hold <= {reset_hold[0], 1'b0};
        end
    end
endmodule
