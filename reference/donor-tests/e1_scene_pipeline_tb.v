`timescale 1ns/1ps
module e1_scene_pipeline_tb;
    reg clk=0, rst=1, vs=1, de=0, key_n=1, emergency=0;
    wire [23:0] scene_rgb, osd_rgb, axis_rgb;
    wire [1:0] scene;
    wire ohs, ovs, ode, user, valid, last;
    integer x, y, active_pixels=0, sof=0, eol=0;
    integer px0=0, py0=0;
    reg d0=0;
    reg [1:0] expected_scene=0;
    scene_video #(.DEBOUNCE_CYCLES(4)) source(
        .clk(clk), .rst(rst), .vs(vs), .de(de), .background_rgb(24'hxxxxxx),
        .key_event_n(key_n), .sw_emergency(emergency), .sw_clear(1'b0),
        .rgb(scene_rgb), .scene_id(scene), .requested_scene_id(),
        .last_event_scene(), .event_trigger(), .scene_request(), .scene_commit(),
        .request_pending(), .latency_valid(), .latency_cycles(),
        .request_count(), .ignored_count(), .commit_count()
    );
    cover_passthrough overlay(.clk(clk),.rst(rst),.hs(1'b0),.vs(vs),.de(de),
        .rgb(scene_rgb),
        .hs_out(ohs),.vs_out(ovs),.de_out(ode),.rgb_out(osd_rgb));
    video_rgb_to_axis_640x480 axis(clk,rst,ovs,ode,osd_rgb,user,valid,last,axis_rgb);
    always #5 clk=~clk;
    always @(posedge clk) begin
        if(rst) d0=0;
        else begin
            #1;
            if(valid!==d0) $fatal(1,"M3+E1 valid delay mismatch");
            if(valid) begin
                if (^axis_rgb === 1'bx) $fatal(1,"Unknown pixel escaped the alert pipeline");
                active_pixels=active_pixels+1;
                if(user) sof=sof+1; if(last) eol=eol+1;
                if(user!==(px0==0 && py0==0) || last!==(px0==639))
                    $fatal(1,"M3+E1 SOF/EOL moved");
                if (expected_scene==1 || expected_scene==2) begin
                    if ((px0>=300 && px0<340 && ((py0>=128 && py0<320) || (py0>=352 && py0<392))) &&
                        axis_rgb!==24'hffffff)
                        $fatal(1,"Alert marker did not reach the cover path");
                    if (!((px0>=300 && px0<340 && ((py0>=128 && py0<320) || (py0>=352 && py0<392)))) &&
                        axis_rgb!==(expected_scene==1 ? 24'he0a020 : 24'hc82020))
                        $fatal(1,"Alert cover color mismatch");
                end
            end
            d0=de; px0=x; py0=y;
        end
    end
    task blank;
        input v;
        input integer cycles;
        integer i;
        begin
            for(i=0;i<cycles;i=i+1) begin
                @(negedge clk); vs=v; de=0;
                @(posedge clk); #2;
            end
        end
    endtask
    task frame;
        input [1:0] target;
        begin
            expected_scene=target;
            blank(0,10);
            if(scene!==target) $fatal(1,"M3 scene failed to commit");
            for(y=0;y<480;y=y+1) begin
                for(x=0;x<640;x=x+1) begin
                    @(negedge clk); de=1;
                    @(posedge clk); #2;
                end
                blank(0,8);
            end
            blank(0,8);
        end
    endtask
    initial begin
        blank(1,4); rst=0; blank(1,10);
        key_n=0; blank(1,12); key_n=1;
        frame(1);
        emergency=1; blank(1,12); key_n=0; blank(1,12); key_n=1;
        frame(2);
        if(active_pixels!=614400 || sof!=2 || eol!=960) $fatal(1,"Pipeline frame coverage mismatch");
        $display("PASS: cover path preserves two full alert frames without OSD panels, borders or text");
        $finish;
    end
    initial begin #15000000; $fatal(1,"E1 integration timeout"); end
endmodule
