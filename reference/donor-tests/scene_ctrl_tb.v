`timescale 1ns/1ps
module scene_ctrl_tb;
    reg clk=0, rst=1, frame_boundary=0, event_trigger=0, clear_request=0;
    reg [1:0] event_scene=0;
    wire scene_request, scene_commit, request_pending, latency_valid;
    wire [1:0] scene_id, requested_scene_id, last_event_scene;
    wire [31:0] latency_cycles, request_count, ignored_count, commit_count;
    integer checks=0;
    scene_ctrl #(.NOTICE_HOLD_FRAMES(3), .EMERGENCY_HOLD_FRAMES(4)) dut(
        .clk(clk), .rst(rst), .frame_boundary(frame_boundary),
        .event_trigger(event_trigger), .event_scene(event_scene),
        .clear_request(clear_request), .scene_request(scene_request),
        .requested_scene_id(requested_scene_id), .request_pending(request_pending),
        .scene_commit(scene_commit), .scene_id(scene_id),
        .latency_cycles(latency_cycles), .latency_valid(latency_valid),
        .last_event_scene(last_event_scene), .request_count(request_count),
        .ignored_count(ignored_count), .commit_count(commit_count)
    );
    always #5 clk=~clk;
    task tick;
        input boundary, trigger;
        input [1:0] id;
        input clear;
        begin
            @(negedge clk);
            frame_boundary=boundary; event_trigger=trigger;
            event_scene=id; clear_request=clear;
            @(posedge clk); #1;
            checks=checks+1;
        end
    endtask
    task reset;
        begin
            @(negedge clk); rst=1;
            @(posedge clk); #1;
            if (scene_id!==0 || request_pending!==0 || scene_commit!==0 ||
                scene_request!==0 || latency_valid!==0 || request_count!==0 ||
                ignored_count!==0 || commit_count!==0 || latency_cycles!==0)
                $fatal(1,"Reset did not cancel active/pending scene and counters");
            @(negedge clk); rst=0; event_trigger=0; frame_boundary=0; clear_request=0;
        end
    endtask
    initial begin
        reset();
        tick(0,1,1,0);
        if (!scene_request || !request_pending || scene_id!=0 || scene_commit)
            $fatal(1,"Notice must wait for a frame boundary");
        repeat(7) tick(0,0,0,0);
        tick(1,0,0,0);
        if (!scene_commit || scene_id!=1 || request_pending || latency_cycles!=8)
            $fatal(1,"Notice commit/latency mismatch");
        tick(0,1,1,0);
        tick(0,1,0,0);
        if (request_count!=1 || ignored_count!=2 || scene_id!=1)
            $fatal(1,"Equal and lower priority changed active notice");
        tick(0,1,2,0);
        repeat(2) tick(0,0,0,0);
        tick(1,0,0,0);
        if (scene_id!=2 || !scene_commit || latency_cycles!=3 || last_event_scene!=2)
            $fatal(1,"Emergency did not preempt active notice");
        tick(0,1,2,0); tick(0,1,1,0); tick(0,1,0,0); tick(0,1,3,0);
        if (request_count!=2 || ignored_count!=6 || scene_id!=2)
            $fatal(1,"Equal/lower/reserved requests must be rejected");
        repeat(3) begin
            tick(1,0,0,0);
            if (scene_id!=2 || scene_commit) $fatal(1,"Emergency expired early");
        end
        tick(1,0,0,0);
        if (scene_id!=0 || !scene_commit || latency_cycles!=3)
            $fatal(1,"Emergency did not return to background at expiry");
        tick(0,0,0,0);
        if (scene_commit || scene_request) $fatal(1,"Handshake pulse wider than one cycle");

        reset();
        tick(0,1,1,0); tick(0,1,1,0); tick(0,1,0,0);
        tick(0,1,2,0); tick(0,1,1,0); tick(1,0,0,0);
        if (scene_id!=2 || request_count!=2 || ignored_count!=3 || latency_cycles!=2)
            $fatal(1,"Pending arbitration or first-arrival latency mismatch");
        reset();
        tick(0,1,1,0); tick(1,1,2,0);
        if (scene_id!=2 || !scene_request || !scene_commit || latency_cycles!=0)
            $fatal(1,"Higher request on commit edge must win with latency zero");
        tick(0,0,0,1);
        if (scene_id!=2 || scene_commit) $fatal(1,"Clear tore the current frame");
        tick(0,1,2,0); tick(1,0,0,0);
        if (scene_id!=0 || !scene_commit || request_pending)
            $fatal(1,"Latched clear must return to background on boundary");
        tick(1,1,1,0);
        if (scene_id!=1 || latency_cycles!=0) $fatal(1,"Repeated event after clear failed");
        repeat(2) tick(1,0,0,0);
        tick(1,1,1,0);
        if (scene_id!=0 || request_count!=3)
            $fatal(1,"Equal-priority repeat must not extend the hold duration");
        tick(1,1,1,0);
        if (scene_id!=1 || request_count!=4) $fatal(1,"Repeat after expiry failed");
        tick(1,1,2,1);
        if (scene_id!=0 || request_count!=4 || request_pending)
            $fatal(1,"Explicit clear must win over an event on the same edge");
        tick(0,1,2,0);
        reset(); tick(1,0,0,0);
        if (scene_id!=0 || scene_commit) $fatal(1,"Reset left a stale pending commit");
        tick(1,1,0,0);
        if (!scene_request || !scene_commit || scene_id!=0 || latency_cycles!=0)
            $fatal(1,"Ordinary priority idle request failed");
        $display("PASS: scene_ctrl, %0d cycles; arbitration, pending replacement, same-edge commit, clear, expiry, reset and exact latency",checks);
        $finish;
    end
    initial begin #100000; $fatal(1,"scene_ctrl test timeout"); end
endmodule
