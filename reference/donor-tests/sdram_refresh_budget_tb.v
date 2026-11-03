`timescale 1ns / 1ps
`include "global_def.v"

// Exercise the actual macros used by the SDRAM refresh controller. Its
// counter visits 0 through SELF_REFRESH_INTERVAL inclusive before wrapping.
module sdram_refresh_budget_tb;
    localparam integer PERIOD_NS = `SDR_CLK_PERIOD;
    localparam integer LAST_COUNT = `SELF_REFRESH_INTERVAL;
    // EM638325 requires 4096 AUTO REFRESH commands per 64 ms. Its
    // 2048 row-address count is not the required refresh-command count.
    localparam integer MAX_INTERVAL_NS = 64000000 / 4096;
    initial begin
        if (LAST_COUNT <= 10 || LAST_COUNT >= 16384)
            $fatal(1, "refresh count invalid: period=%0d last_count=%0d", PERIOD_NS, LAST_COUNT);
        if ((LAST_COUNT + 1) * PERIOD_NS > MAX_INTERVAL_NS)
            $fatal(1, "refresh interval exceeds retention budget: %0d ns > %0d ns",
                   (LAST_COUNT + 1) * PERIOD_NS, MAX_INTERVAL_NS);
        if ((LAST_COUNT + 2) * PERIOD_NS <= MAX_INTERVAL_NS)
            $fatal(1, "refresh count is not the largest safe inclusive count");
        $display("PASS: SDRAM period=%0d ns, refresh=%0d cycles / %0d ns, limit=%0d ns",
                 PERIOD_NS, LAST_COUNT + 1, (LAST_COUNT + 1) * PERIOD_NS, MAX_INTERVAL_NS);
        $finish;
    end
endmodule
