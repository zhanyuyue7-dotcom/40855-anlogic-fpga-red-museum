`timescale 1ns/1ps
module scene_audio_tb;
    reg vclk=0, aclk=0, rst=1;
    reg [1:0] scene=0;
    wire [1:0] audio_scene;
    wire bclk, lrck, dout;
    integer sample_edges=0, bit_edges=0, last_lr_edge=0, switches=0;
    integer previous_bit=0;
    reg previous_bclk=0, previous_lrck=0;
    reg [1:0] previous_scene=0;
    reg [31:0] previous_phase=0;
    reg was_sample_edge=0;
    reg [63:0] word=0;
    reg [23:0] left_word=0;
    reg have_left=0;
    scene_audio_cdc cdc(vclk,aclk,rst,scene,audio_scene);
    hdmi_audio_tone_i2s_64fs #(.NOTE_HOLD_FRAMES(12)) tone(
        .I_mclk(aclk), .I_rst(rst), .I_scene(audio_scene),
        .O_i2s_BCLK(bclk), .O_i2s_LRCK(lrck), .O_i2s_DOUT(dout)
    );
    always #5 vclk=~vclk;
    always #13 aclk=~aclk;
    // Decode transmitted bits, including identical signed left/right samples.
    always @(posedge bclk) if (!rst) begin
        word={word[62:0],dout};
        bit_edges=bit_edges+1;
        if (bit_edges%64==0) begin
            if (word[39:0]!==0) $fatal(1,"I2S padding changed");
            if (!lrck) begin left_word=word[63:40]; have_left=1; end
            else if (have_left && word[63:40]!==left_word) $fatal(1,"Left/right samples split on scene change");
        end
    end
    always @(posedge aclk) begin
        previous_bit=tone.S_bit_cnt;
        was_sample_edge=bclk && previous_bit==63 && lrck;
        previous_phase=tone.S_phase_acc;
        #1;
        if (!rst) begin
            if (bclk===previous_bclk) $fatal(1,"BCLK stopped during tone switch");
            if (lrck!==previous_lrck) begin
                if (last_lr_edge!=0 && ($time-last_lr_edge)!=3328) $fatal(1,"LRCK cadence changed");
                last_lr_edge=$time;
            end
            if (tone.S_active_scene!==previous_scene) begin
                if (!was_sample_edge) $fatal(1,"Tone switch split a stereo sample");
                switches=switches+1;
            end else if (was_sample_edge) begin
                sample_edges=sample_edges+1;
                if (previous_scene==1 && tone.S_phase_acc!==previous_phase+32'd78741067)
                    $fatal(1,"Notice is not the expected 880Hz phase increment");
                if (previous_scene==2 && tone.S_phase_acc!==previous_phase+32'd157482134)
                    $fatal(1,"Emergency is not the expected 1760Hz phase increment");
            end
            previous_bclk=bclk; previous_lrck=lrck; previous_scene=tone.S_active_scene;
        end else begin
            previous_bclk=0; previous_lrck=0; previous_scene=0;
            last_lr_edge=0; bit_edges=0; word=0; have_left=0;
        end
    end
    task hold_scene;
        input [1:0] id;
        begin
            @(negedge vclk); scene=id;
            repeat(1800) @(negedge aclk);
            if (audio_scene!==id || tone.S_active_scene!==id) $fatal(1,"Audio mailbox did not deliver scene %0d",id);
        end
    endtask
    initial begin
        repeat(5) @(negedge aclk); rst=0;
        hold_scene(0); hold_scene(1); hold_scene(2); hold_scene(0); hold_scene(2);
        // Multiple source updates while mailbox is busy must converge to latest.
        @(negedge vclk); scene=1;
        @(negedge vclk); scene=0;
        @(negedge vclk); scene=2;
        hold_scene(2);
        if (switches<4 || sample_edges<30) $fatal(1,"Insufficient audio coverage");
        rst=1; repeat(4) @(negedge aclk); scene=0; rst=0;
        hold_scene(0);
        $display("PASS: bundled-data mailbox, rapid updates, reset, continuous BCLK/LRCK, identical stereo samples and sample-boundary 880/1760Hz selection");
        $finish;
    end
    initial begin #1000000; $fatal(1,"Audio test timeout"); end
endmodule
