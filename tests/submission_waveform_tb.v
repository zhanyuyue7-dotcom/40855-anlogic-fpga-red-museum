`timescale 1ns/1ps
// Record the existing self-checking production FIFO/frame-bridge regression.
module submission_waveform_tb;
    hxfp_frame_bridge_tb dut();
    initial begin
        $dumpfile("verification/waveforms/hxfp-frame-bridge.vcd");
        $dumpvars(0, dut);
    end
endmodule
