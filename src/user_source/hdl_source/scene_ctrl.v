// Local M3 control logic. Every input and output is in the pixel-clock domain.
// Scene encoding is also priority: 0 background, 1 notice, 2 emergency; 3 invalid.
module scene_ctrl #(
    parameter integer NOTICE_HOLD_FRAMES = 120,
    parameter integer EMERGENCY_HOLD_FRAMES = 180
)(
    input wire clk, rst, frame_boundary,
    input wire event_trigger,
    input wire [1:0] event_scene,
    input wire clear_request,
    output reg scene_request,
    output reg [1:0] requested_scene_id,
    output reg request_pending,
    output reg scene_commit,
    output reg [1:0] scene_id,
    output reg [31:0] latency_cycles,
    output reg latency_valid,
    output reg [1:0] last_event_scene,
    output reg [31:0] request_count, ignored_count, commit_count
);
    reg [1:0] pending_scene;
    reg [31:0] pending_age;
    reg [15:0] hold_frames;
    reg clear_pending;
    wire accept_event = event_trigger && event_scene != 2'd3 &&
        !clear_request && !clear_pending &&
        (!request_pending || event_scene > pending_scene) &&
        (event_scene > scene_id || (event_scene == 0 && scene_id == 0));
    wire [31:0] next_age = pending_age == 32'hffffffff ?
        pending_age : pending_age + 32'd1;

    function [15:0] hold_for;
        input [1:0] id;
        begin
            case (id)
                2'd1: hold_for = NOTICE_HOLD_FRAMES;
                2'd2: hold_for = EMERGENCY_HOLD_FRAMES;
                default: hold_for = 16'd0;
            endcase
        end
    endfunction

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            scene_request <= 0; requested_scene_id <= 0; request_pending <= 0;
            scene_commit <= 0; scene_id <= 0;
            pending_scene <= 0; pending_age <= 0; hold_frames <= 0;
            clear_pending <= 0; latency_cycles <= 0; latency_valid <= 0;
            last_event_scene <= 0;
            request_count <= 0; ignored_count <= 0; commit_count <= 0;
        end else begin
            scene_request <= 0;
            scene_commit <= 0;
            if (accept_event) begin
                scene_request <= 1;
                requested_scene_id <= event_scene;
                request_count <= request_count + 1'b1;
            end else if (event_trigger) begin
                ignored_count <= ignored_count + 1'b1;
            end

            if (frame_boundary) begin
                if (clear_request || clear_pending) begin
                    clear_pending <= 0;
                    request_pending <= 0;
                    hold_frames <= 0;
                    scene_id <= 0;
                    if (scene_id != 0) begin
                        scene_commit <= 1;
                        commit_count <= commit_count + 1'b1;
                    end
                end else if (accept_event || request_pending) begin
                    // A newly accepted higher event supersedes the queued event
                    // even when it arrives exactly on the frame boundary.
                    scene_id <= accept_event ? event_scene : pending_scene;
                    hold_frames <= hold_for(accept_event ? event_scene : pending_scene);
                    request_pending <= 0;
                    scene_commit <= 1;
                    commit_count <= commit_count + 1'b1;
                    latency_cycles <= accept_event ? 32'd0 : next_age;
                    latency_valid <= 1;
                    last_event_scene <= accept_event ? event_scene : pending_scene;
                end else if (scene_id != 0) begin
                    if (hold_frames <= 1) begin
                        scene_id <= 0;
                        hold_frames <= 0;
                        scene_commit <= 1;
                        commit_count <= commit_count + 1'b1;
                    end else begin
                        hold_frames <= hold_frames - 1'b1;
                    end
                end
            end else if (clear_request || clear_pending) begin
                clear_pending <= 1;
                request_pending <= 0;
            end else if (accept_event) begin
                request_pending <= 1;
                pending_scene <= event_scene;
                pending_age <= 0;
            end else if (request_pending) begin
                pending_age <= next_age;
            end
        end
    end
endmodule
