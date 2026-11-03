// In-place RGB selection: DE/HS/VS retain the existing upstream latency.
// Alerts use only registers/combinational graphics, never TF or SDRAM contents.
module scene_video #(
    parameter integer DEBOUNCE_CYCLES = 500000,
    parameter integer NOTICE_HOLD_FRAMES = 120,
    parameter integer EMERGENCY_HOLD_FRAMES = 180
)(
    input wire clk, rst, vs, de,
    input wire [23:0] background_rgb,
    input wire key_event_n, sw_emergency, sw_clear,
    input wire network_event_valid,
    input wire [1:0] network_event_scene,
    input wire network_clear_request,
    output wire [23:0] rgb,
    output wire [1:0] scene_id, requested_scene_id, last_event_scene,
    output wire event_trigger, scene_request, scene_commit, request_pending,
    output wire latency_valid,
    output wire [31:0] latency_cycles, request_count, ignored_count, commit_count
);
    (* async_reg = "true" *) reg [1:0] reset_sync;
    reg vs_prev, de_prev;
    reg [9:0] x;
    reg [9:0] y;
    wire scene_rst = reset_sync[1];
    wire frame_boundary = vs_prev && !vs && !de;
    wire [1:0] event_scene;
    wire clear_request;
    wire mark = x >= 300 && x < 340 &&
        ((y >= 128 && y < 320) || (y >= 352 && y < 392));

    always @(posedge clk or posedge rst) begin
        if (rst) reset_sync <= 2'b11;
        else reset_sync <= {reset_sync[0], 1'b0};
    end
    always @(posedge clk or posedge scene_rst) begin
        if (scene_rst) begin
            vs_prev <= 0; de_prev <= 0; x <= 0; y <= 0;
        end else begin
            vs_prev <= vs; de_prev <= de;
            if (frame_boundary) begin x <= 0; y <= 0; end
            else if (de) x <= x + 1'b1;
            else if (de_prev) begin x <= 0; y <= y + 1'b1; end
        end
    end
    scene_inputs #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_inputs(
        .clk(clk), .rst(scene_rst), .key_event_n(key_event_n),
        .sw_emergency(sw_emergency), .sw_clear(sw_clear),
        .network_event_valid(network_event_valid),
        .network_event_scene(network_event_scene),
        .network_clear_request(network_clear_request),
        .event_trigger(event_trigger), .event_scene(event_scene),
        .clear_request(clear_request)
    );
    scene_ctrl #(.NOTICE_HOLD_FRAMES(NOTICE_HOLD_FRAMES),
        .EMERGENCY_HOLD_FRAMES(EMERGENCY_HOLD_FRAMES)) u_ctrl(
        .clk(clk), .rst(scene_rst), .frame_boundary(frame_boundary),
        .event_trigger(event_trigger), .event_scene(event_scene),
        .clear_request(clear_request), .scene_request(scene_request),
        .requested_scene_id(requested_scene_id), .request_pending(request_pending),
        .scene_commit(scene_commit), .scene_id(scene_id),
        .latency_cycles(latency_cycles), .latency_valid(latency_valid),
        .last_event_scene(last_event_scene), .request_count(request_count),
        .ignored_count(ignored_count), .commit_count(commit_count)
    );
    assign rgb = !de ? 24'd0 : scene_id == 0 ? background_rgb :
        mark ? 24'hffffff : scene_id == 1 ? 24'he0a020 : 24'hc82020;
endmodule
