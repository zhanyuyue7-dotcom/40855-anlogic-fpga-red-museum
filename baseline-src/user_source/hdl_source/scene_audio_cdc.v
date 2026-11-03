// Bundled-data toggle/ack mailbox. Data stays stable until the audio side
// acknowledges it; rapidly changing scenes coalesce to the latest commit.
module scene_audio_cdc(
    input wire video_clk, audio_clk, rst,
    input wire [1:0] scene_id,
    output reg [1:0] audio_scene
);
    reg [1:0] held_scene;
    reg request_toggle, acknowledge_toggle;
    (* async_reg = "true" *) reg [1:0] ack_sync, request_sync;
    (* async_reg = "true" *) reg [1:0] video_reset, audio_reset;
    always @(posedge video_clk or posedge rst) begin
        if (rst) video_reset <= 2'b11;
        else video_reset <= {video_reset[0], 1'b0};
    end
    always @(posedge audio_clk or posedge rst) begin
        if (rst) audio_reset <= 2'b11;
        else audio_reset <= {audio_reset[0], 1'b0};
    end
    always @(posedge video_clk or posedge video_reset[1]) begin
        if (video_reset[1]) begin
            held_scene <= 0; request_toggle <= 0; ack_sync <= 0;
        end else begin
            ack_sync <= {ack_sync[0], acknowledge_toggle};
            if (ack_sync[1] == request_toggle && held_scene != scene_id) begin
                held_scene <= scene_id;
                request_toggle <= ~request_toggle;
            end
        end
    end
    always @(posedge audio_clk or posedge audio_reset[1]) begin
        if (audio_reset[1]) begin
            request_sync <= 0; acknowledge_toggle <= 0; audio_scene <= 0;
        end else begin
            request_sync <= {request_sync[0], request_toggle};
            if (request_sync[1] != acknowledge_toggle) begin
                audio_scene <= held_scene;
                acknowledge_toggle <= request_sync[1];
            end
        end
    end
endmodule
