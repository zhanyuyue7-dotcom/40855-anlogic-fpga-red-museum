`timescale 1ns/1ps
module transition_recovery_reset_tb;
    reg clk=0, rst=1, recovery_toggle=0;
    wire recovery_reset;
    integer high_cycles;
    transition_recovery_reset dut(
        .clk(clk), .rst(rst), .recovery_toggle(recovery_toggle),
        .recovery_reset(recovery_reset));
    always #5 clk=~clk;
    task tick; begin @(posedge clk); #1; @(negedge clk); end endtask
    initial begin
        repeat(3) tick; rst=0; repeat(3) tick;
        if(recovery_reset) $fatal(1,"recovery reset not idle");
        recovery_toggle=1; tick; recovery_toggle=1;
        high_cycles=0;
        repeat(6) begin tick; if(recovery_reset) high_cycles=high_cycles+1; end
        if(high_cycles < 2) $fatal(1,"recovery reset pulse too short");
        if(recovery_reset) $fatal(1,"recovery reset did not release");
        $display("PASS: recovery toggle creates a bounded video-domain re-arm reset");
        $finish;
    end
    initial begin #10000; $fatal(1,"recovery reset timeout"); end
endmodule
