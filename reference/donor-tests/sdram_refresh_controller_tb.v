`timescale 1ns / 1ps
`include "global_def.v"

// The runner compiles the unchanged, public refresh scheduling logic from
// sdr_init_ref.enc.v; only its protected command encoder is omitted.
module sdram_refresh_controller_tb;
    reg clk = 0, rst = 1, ack = 0, busy = 0;
    wire request, initialized, refresh_valid;
    integer cycles = 0, previous_request = -1, requests = 0;
    localparam integer PERIOD = `SDR_CLK_PERIOD;
    localparam integer MAX_CYCLES = (64000000 / 4096) / PERIOD;
    always #(PERIOD / 2) clk = ~clk;
    sdr_init_ref dut(.Sdr_clk(clk), .Rst(rst),
        .Sdr_init_req(1'b0), .Sdr_init_mode(4'd0),
        .Sdr_init_done(initialized), .App_ref_req(1'b0),
        .Sdr_ref_req(request), .Sdr_ref_ack(ack), .Sdr_rw_vld(busy),
        .Sdr_init_ref_vld(refresh_valid));
    always @(posedge clk) begin
        #1;
        if (initialized) begin
            cycles = cycles + 1;
            if (request) begin
                if (previous_request >= 0 && cycles - previous_request > MAX_CYCLES)
                    $fatal(1, "refresh cadence too slow: %0d cycles > %0d", cycles - previous_request, MAX_CYCLES);
                previous_request = cycles;
                requests = requests + 1;
            end
        end
    end
    initial begin
        repeat(4) @(negedge clk);
        rst = 0;
        wait(initialized);
        repeat(8 * MAX_CYCLES) @(negedge clk);
        if (requests < 7) $fatal(1, "periodic refresh absent/too slow: %0d requests", requests);
        // Acknowledge a real request after a delayed/busy interval. The
        // request scheduler must keep ticking after the refresh retires.
        busy = 1;
        wait(request); repeat(8) @(negedge clk);
        busy = 0; ack = 1; @(negedge clk); ack = 0;
        @(negedge clk);
        if (!refresh_valid) $fatal(1, "acknowledged refresh did not become valid");
        repeat(23) @(negedge clk);
        if (refresh_valid) $fatal(1, "refresh did not retire after bounded ack pipeline");
        $display("PASS: real refresh scheduler, %0d periodic requests, initialization and delayed ACK retirement", requests);
        $finish;
    end
    initial begin #10000000; $fatal(1, "refresh controller timeout"); end
endmodule
