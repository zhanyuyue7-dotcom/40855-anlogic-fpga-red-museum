// Persistent ordinary-scene OSD visibility fade.
// Each trigger toggles the target visibility. The level moves one smooth
// frame step at each VS falling-edge boundary, independently of image fades.
module ui_visibility_fade #(
    parameter integer ENABLE = 1
)(
    input wire clk, rst, vs, de,
    input wire trigger_toggle,
    output wire [5:0] fade_level,
    output wire visible,
    output wire transition_active
);
    localparam [5:0] FULL_LEVEL = 6'd32;
    reg vs_prev;
    reg [5:0] level;
    reg target_visible;
    (* async_reg = "true" *) reg [1:0] trigger_sync;
    reg trigger_seen;
    wire frame_boundary = vs_prev && !vs && !de;
    wire trigger_pulse = trigger_sync[1] ^ trigger_seen;

    assign fade_level = ENABLE ? level : FULL_LEVEL;
    assign visible = ENABLE ? (level != 0) : 1'b1;
    assign transition_active = ENABLE && ((target_visible && level != FULL_LEVEL) ||
                                          (!target_visible && level != 0));

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            vs_prev <= 1'b0;
            level <= FULL_LEVEL;
            target_visible <= 1'b1;
            trigger_sync <= 2'b00;
            trigger_seen <= 1'b0;
        end else begin
            vs_prev <= vs;
            trigger_sync <= {trigger_sync[0], trigger_toggle};
            if (!ENABLE) begin
                level <= FULL_LEVEL;
                target_visible <= 1'b1;
                trigger_seen <= trigger_sync[1];
            end else begin
                if (trigger_pulse) begin
                    trigger_seen <= trigger_sync[1];
                    target_visible <= ~target_visible;
                end
                if (frame_boundary) begin
                    if (target_visible && level != FULL_LEVEL)
                        level <= level + 1'b1;
                    else if (!target_visible && level != 0)
                        level <= level - 1'b1;
                end
            end
        end
    end
endmodule
