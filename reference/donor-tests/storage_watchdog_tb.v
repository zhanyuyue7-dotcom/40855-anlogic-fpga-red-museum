`timescale 1ns/1ps
module storage_watchdog_tb;
    reg clk=0,rst=1,sd_init=0,scan_done=0,load_busy=0,source_done=0,write_done=0;
    reg [2:0] found_count=0;
    wire recovery_pulse,recovery_toggle,fault_active;
    wire [2:0] fault_code;
    wire [31:0] recovery_count,last_timeout_cycles;
    integer prior_count;
    storage_watchdog #(.INIT_TIMEOUT_CYCLES(4),.SCAN_TIMEOUT_CYCLES(5),
        .LOAD_TIMEOUT_CYCLES(6),.EMPTY_TIMEOUT_CYCLES(4)) dut(
        .clk(clk),.rst(rst),.sd_init_done(sd_init),.scan_done(scan_done),
        .found_count(found_count),.load_busy(load_busy),
        .source_done(source_done),.write_done(write_done),
        .recovery_pulse(recovery_pulse),.recovery_toggle(recovery_toggle),
        .fault_active(fault_active),.fault_code(fault_code),
        .recovery_count(recovery_count),.last_timeout_cycles(last_timeout_cycles));
    always #5 clk=~clk;
    task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
    task expect_fault;
        input [2:0] expected_code;
        input integer max_cycles;
        integer i,seen;
        begin
            prior_count=recovery_count;seen=0;
            for(i=0;i<max_cycles;i=i+1) begin
                tick;
                if(recovery_pulse) begin
                    seen=seen+1;
                    if(fault_code!==expected_code || !fault_active)
                        $fatal(1,"wrong fault code expected=%0d got=%0d",expected_code,fault_code);
                end
            end
            if(seen!=1 || recovery_count!=prior_count+1)
                $fatal(1,"fault was not one bounded recovery pulse code=%0d seen=%0d",expected_code,seen);
            tick;
            if(recovery_pulse) $fatal(1,"recovery pulse stuck high");
        end
    endtask
    task healthy;
        begin
            sd_init=1;scan_done=1;found_count=4;load_busy=0;source_done=0;write_done=0;
            repeat(3) tick;
            if(fault_active || fault_code!=0) $fatal(1,"healthy idle did not clear latched fault");
        end
    endtask
    initial begin
        repeat(3) tick;rst=0;
        expect_fault(1,4); // SD initialization stall / no card
        healthy;
        scan_done=0;expect_fault(2,6); // sector scan stall
        healthy;
        load_busy=1;source_done=0;write_done=0;expect_fault(3,7); // source missing
        healthy;
        load_busy=1;source_done=1;write_done=0;expect_fault(4,7); // SDRAM completion missing
        healthy;
        found_count=0;expect_fault(5,5); // scan finished, no valid BMP
        healthy;
        load_busy=1;source_done=1;write_done=1;expect_fault(6,7); // scheduler failed to retire
        healthy;
        if(recovery_count!=6 || last_timeout_cycles==0)
            $fatal(1,"recovery counters incomplete count=%0d last=%0d",recovery_count,last_timeout_cycles);
        $display("PASS: bounded init/scan/source/SDRAM/invalid-image/retire recovery, one-cycle pulses, counters and healthy clear");
        $finish;
    end
    initial begin #100000;$fatal(1,"storage watchdog timeout");end
endmodule
