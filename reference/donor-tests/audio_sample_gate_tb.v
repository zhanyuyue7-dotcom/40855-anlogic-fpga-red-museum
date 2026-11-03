`timescale 1ns/1ps
module audio_sample_gate_tb;
    reg enable=0, valid_in=0;
    reg [23:0] left_in=24'h123456, right_in=24'habcdef;
    wire valid_out;
    wire [23:0] left_out, right_out;
    audio_sample_gate dut(enable,valid_in,left_in,right_in,valid_out,left_out,right_out);
    initial begin
        #1;
        if(left_out!==0 || right_out!==0 || valid_out!==0)
            $fatal(1,"reset/default mute leaked an audio sample");
        valid_in=1;#1;
        if(left_out!==0 || right_out!==0 || valid_out!==1)
            $fatal(1,"mute must keep valid timing while forcing digital silence");
        enable=1;#1;
        if(left_out!==left_in || right_out!==right_in || valid_out!==1)
            $fatal(1,"enabled audio did not pass samples exactly");
        enable=0;left_in=24'hffffff;right_in=24'h800000;#1;
        if(left_out!==0 || right_out!==0)
            $fatal(1,"mute leaked changed samples");
        $display("PASS: SW4 audio gate defaults to digital silence, preserves valid cadence and passes enabled samples exactly");
        $finish;
    end
endmodule
