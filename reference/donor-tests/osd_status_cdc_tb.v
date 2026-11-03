`timescale 1ns/1ps
module osd_status_cdc_tb;
    reg source_clk=0, pixel_clk=0, rst=1;
    reg [3:0] source_state=0;
    wire [3:0] pixel_state;
    osd_status_cdc dut(source_clk,pixel_clk,rst,source_state,pixel_state);
    always #5 source_clk=~source_clk;
    always #13 pixel_clk=~pixel_clk;
    task settle;
        input [3:0] value;
        begin
            @(negedge source_clk); source_state=value;
            repeat(20) @(negedge pixel_clk);
            if(pixel_state!==value) $fatal(1,"State mailbox did not deliver %0d",value);
        end
    endtask
    initial begin
        repeat(5) @(negedge pixel_clk); rst=0;
        settle(1); settle(2); settle(3); settle(4); settle(0);
        @(negedge source_clk); source_state=3;
        @(negedge source_clk); source_state=4;
        @(negedge source_clk); source_state=1;
        settle(2);
        rst=1; repeat(4) @(negedge pixel_clk);
        if(pixel_state!==0) $fatal(1,"Mailbox reset did not clear status");
        source_state=0; rst=0; settle(4);
        $display("PASS: OSD state mailbox, unrelated clocks, all BMP states, rapid updates, eventual latest state and reset");
        $finish;
    end
    initial begin #100000; $fatal(1,"OSD mailbox timeout"); end
endmodule
