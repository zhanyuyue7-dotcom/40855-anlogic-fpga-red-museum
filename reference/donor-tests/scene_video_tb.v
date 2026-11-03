`timescale 1ns/1ps
module scene_video_tb;
    reg clk=0, rst=1, vs=1, de=0, key_n=1, emergency=0, clear_sw=0;
    reg [23:0] background=24'h123456;
    wire [23:0] rgb, axis_rgb;
    wire [1:0] scene_id, requested, last_scene;
    wire trigger, request, commit, pending, latency_valid, user, valid, last;
    wire [31:0] latency, requests, ignored, commits;
    integer cycle=0, request_cycle=0, x, y, sof=0, eol=0, pixels=0, commit_seen=0;
    integer csv;
    reg [1023:0] csv_path;
    scene_video #(.DEBOUNCE_CYCLES(4), .NOTICE_HOLD_FRAMES(3), .EMERGENCY_HOLD_FRAMES(3)) dut(
        .clk(clk), .rst(rst), .vs(vs), .de(de), .background_rgb(background),
        .key_event_n(key_n), .sw_emergency(emergency), .sw_clear(clear_sw),
        .rgb(rgb), .scene_id(scene_id), .requested_scene_id(requested),
        .last_event_scene(last_scene), .event_trigger(trigger), .scene_request(request),
        .scene_commit(commit), .request_pending(pending), .latency_valid(latency_valid),
        .latency_cycles(latency), .request_count(requests), .ignored_count(ignored),
        .commit_count(commits)
    );
    video_rgb_to_axis_640x480 axis(clk,rst,vs,de,rgb,user,valid,last,axis_rgb);
    always #5 clk=~clk;
    always @(posedge clk) begin
        cycle=cycle+1;
        #1;
        if (request) request_cycle=cycle;
        if (commit) begin
            if (de || vs) $fatal(1,"Scene commit outside VS blanking boundary");
            commit_seen=commit_seen+1;
            if (scene_id!=0) begin
                if (latency !== cycle-request_cycle) $fatal(1,"Measured latency mismatch");
                if (csv) $fdisplay(csv,"%0d,%0d,%0d,%0d",scene_id,request_cycle,cycle,latency);
            end
        end
    end
    task blank;
        input v;
        input integer n;
        integer i;
        begin
            for (i=0;i<n;i=i+1) begin
                @(negedge clk); vs=v; de=0;
                @(posedge clk); #2;
            end
        end
    endtask
    task frame;
        input [1:0] expected_scene;
        input press_emergency;
        reg [23:0] expected;
        begin
            blank(1,4); blank(0,4);
            for (y=0;y<480;y=y+1) begin
                for (x=0;x<640;x=x+1) begin
                    @(negedge clk); de=1;
                    if (press_emergency && y==200 && x==100) begin emergency=1; key_n=0; end
                    expected = expected_scene==0 ? background :
                        (x>=300 && x<340 && ((y>=128 && y<320)||(y>=352 && y<392))) ?
                        24'hffffff : expected_scene==1 ? 24'he0a020 : 24'hc82020;
                    @(posedge clk); #2;
                    if (scene_id!==expected_scene || !valid || axis_rgb!==expected ||
                        user!==(y==0 && x==0) || last!==(x==639))
                        $fatal(1,"Pixel/SOF/EOL mismatch scene=%0d x=%0d y=%0d rgb=%h expected=%h",scene_id,x,y,axis_rgb,expected);
                    pixels=pixels+1; if(user) sof=sof+1; if(last) eol=eol+1;
                end
                blank(0,8);
            end
        end
    endtask
    initial begin
        csv=0;
        if ($value$plusargs("latency_csv=%s", csv_path)) begin
            csv=$fopen(csv_path,"w");
            if (!csv) $fatal(1,"Cannot create simulation latency CSV");
            $fdisplay(csv,"scene_id,request_cycle,commit_cycle,latency_cycles");
        end
        blank(1,4); rst=0; blank(1,8);
        // Brief bounce cannot trigger; holding a key produces only one event.
        key_n=0; blank(1,1); key_n=1; blank(1,8);
        if (requests!=0) $fatal(1,"Short bounce became an event");
        key_n=0; blank(1,10);
        if (requests!=1 || !pending || scene_id!=0) $fatal(1,"Debounced event not queued");
        key_n=1; blank(1,10);
        frame(1,1); // emergency arrives mid-frame; every pixel must remain notice.
        if (!pending || requests!=2 || scene_id!=1) $fatal(1,"Emergency was blocked during active video");
        // Simulate a TF/SDRAM read stall by holding the upstream pixel bus unknown.
        background=24'hxxxxxx;
        frame(2,0);
        if (requests!=2) $fatal(1,"Long key hold retriggered");
        key_n=1; blank(0,10);
        key_n=0; blank(0,10); key_n=1; blank(0,10);
        if (ignored!=1 || requests!=2) $fatal(1,"Same-priority emergency was not ignored");
        clear_sw=1; blank(0,10);
        if (scene_id!=2) $fatal(1,"Clear changed scene in the middle of a frame");
        background=24'h654321;
        frame(0,0);
        // Trigger another emergency while background remains unavailable.
        clear_sw=0; key_n=0; blank(0,12); key_n=1; blank(0,10);
        background=24'hxxxxxx;
        frame(2,0);
        if (sof!=4 || eol!=1920 || pixels!=1228800 || commit_seen!=4)
            $fatal(1,"Unexpected frame or commit counts");
        rst=1; blank(0,4); rst=0; blank(1,8);
        if (scene_id!=0 || pending || requests!=0 || commits!=0) $fatal(1,"Pipeline reset failed");
        if(csv) $fclose(csv);
        $display("PASS: four full 640x480 frames, 1228800 pixels, 1920 EOL, 4 SOF; mid-frame preemption, debounce, repeated emergency, stalled/unknown background and exact commit latency");
        $finish;
    end
    initial begin #30000000; $fatal(1,"scene video timeout"); end
endmodule
