`timescale 1ns/1ps
module storage_uart_tb;
    reg clk=0, rst=1;
    reg [319:0] status=0;
    wire tx;
    reg [7:0] bytes[0:63];
    reg [7:0] checksum;
    integer i,b;
    scene_status_uart #(.CLK_FREQ_HZ(1000000),.BAUD_RATE(100000),
        .INCLUDE_STORAGE(1),.STATUS_VERSION(3)) dut(
        .clk(clk),.rst(rst),.scene_id(2'd0),.requested_scene_id(2'd1),
        .last_event_scene(2'd1),.request_pending(1'b0),.latency_valid(1'b1),
        .request_count(32'd4),.ignored_count(32'd0),.commit_count(32'd8),
        .latency_cycles(32'd250000),.storage_status(status),.tx(tx)
    );
    always #5 clk=~clk;
    initial begin
        for(i=0;i<40;i=i+1) status[i*8 +:8]=i+1;
        repeat(4) @(negedge clk); rst=0;
        for(i=0;i<64;i=i+1) begin
            @(negedge tx); repeat(5) @(posedge clk); #1;
            if(tx!==0) $fatal(1,"UART start mismatch");
            for(b=0;b<8;b=b+1) begin repeat(10) @(posedge clk); #1; bytes[i][b]=tx; end
            repeat(10) @(posedge clk); #1;
            if(tx!==1) $fatal(1,"UART stop mismatch");
            if(i==5) status=0;
        end
        checksum=0;
        for(i=0;i<64;i=i+1) checksum=checksum^bytes[i];
        if(checksum!==0 || bytes[0]!==8'ha5 || bytes[1]!==8'h33 || bytes[2]!==3)
            $fatal(1,"Storage UART framing/checksum mismatch");
        for(i=23;i<63;i=i+1) if(bytes[i]!==i-22) $fatal(1,"Storage snapshot changed during packet");
        $display("PASS: 64-byte storage UART version 3, coherent captured fields, 8N1 and XOR");
        $finish;
    end
    initial begin #100000; $fatal(1,"Storage UART timeout"); end
endmodule
