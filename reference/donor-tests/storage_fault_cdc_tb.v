`timescale 1ns/1ps
module storage_fault_cdc_tb;
    reg source_clk=0, pixel_clk=0, rst=1;
    reg source_fault=0;
    reg [2:0] source_code=0;
    reg [7:0] source_recovery=0;
    wire pixel_fault;
    wire [2:0] pixel_code;
    wire [7:0] pixel_recovery;
    integer i, observed=0;

    storage_fault_cdc dut(
        .source_clk(source_clk), .pixel_clk(pixel_clk), .rst(rst),
        .source_fault(source_fault), .source_code(source_code),
        .source_recovery(source_recovery), .pixel_fault(pixel_fault),
        .pixel_code(pixel_code), .pixel_recovery(pixel_recovery));

    always #5 source_clk=~source_clk;
    always #13 pixel_clk=~pixel_clk;

    always @(posedge pixel_clk) begin
        #1;
        if(!rst && pixel_recovery != 0) begin
            if (pixel_fault !== pixel_recovery[0] ||
                pixel_code !== pixel_recovery[2:0])
                $fatal(1,"fault mailbox produced a torn snapshot");
            observed=observed+1;
        end
    end

    initial begin
        repeat(5) @(negedge pixel_clk); rst=0;
        for(i=1;i<80;i=i+1) begin
            @(negedge source_clk);
            source_fault = i[0];
            source_code = i[2:0];
            source_recovery = i[7:0];
        end
        repeat(30) @(negedge pixel_clk);
        if(pixel_fault !== source_recovery[0] ||
           pixel_code !== source_recovery[2:0] ||
           pixel_recovery !== source_recovery)
            $fatal(1,"fault mailbox failed to converge to latest complete snapshot");
        if(observed < 10) $fatal(1,"fault mailbox produced too few snapshots");
        rst=1; repeat(4) @(negedge pixel_clk);
        if({pixel_fault,pixel_code,pixel_recovery} !== 0)
            $fatal(1,"fault mailbox reset failed");
        $display("PASS: fault/code/recovery snapshot crosses SD to video atomically");
        $finish;
    end
    initial begin #100000; $fatal(1,"fault mailbox timeout"); end
endmodule
