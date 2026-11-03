`timescale 1ns/1ps
module storage_watchdog_stage_budget_tb;
    reg clk=0,rst=1,sd_init_done=0,scan_done=0,load_busy=0;
    reg source_done=0,write_done=0;
    reg [2:0] found_count=4;
    wire recovery_pulse;
    wire [2:0] fault_code;
    storage_watchdog #(.INIT_TIMEOUT_CYCLES(4),.SCAN_TIMEOUT_CYCLES(5),
        .LOAD_TIMEOUT_CYCLES(6),.EMPTY_TIMEOUT_CYCLES(4)) dut(
        .clk(clk),.rst(rst),.sd_init_done(sd_init_done),.scan_done(scan_done),
        .found_count(found_count),.load_busy(load_busy),.source_done(source_done),
        .write_done(write_done),.recovery_pulse(recovery_pulse),
        .recovery_toggle(),.fault_active(),.fault_code(fault_code),
        .recovery_count(),.last_timeout_cycles());
    always #5 clk=~clk;
    task tick; begin @(posedge clk); #1; @(negedge clk); end endtask
    integer i;
    initial begin
        repeat(3) tick; rst=0;
        repeat(3) tick; // partial INIT phase
        sd_init_done=1; scan_done=0;
        for(i=0;i<5;i=i+1) begin tick; if(recovery_pulse) $fatal(1,"scan budget was shortened"); end
        tick;
        if(!recovery_pulse || fault_code!=2) $fatal(1,"scan phase did not receive full budget");
        $display("PASS: watchdog timer restarts when monitored storage stage changes");
        $finish;
    end
    initial begin #10000; $fatal(1,"stage budget timeout"); end
endmodule
