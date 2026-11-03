`timescale 1ns/1ps
module scene_uart_tb;
    reg clk=0, rst=1;
    reg [1:0] scene=2, requested=2, last_scene=2;
    reg pending=0, latency_valid=1;
    reg [31:0] requests=32'h12345678, ignored=9, commits=11, latency=32'h00abcdef;
    wire tx;
    reg [7:0] bytes [0:23];
    reg [7:0] checksum;
    integer i, bit_n, packet;
    scene_status_uart #(.CLK_FREQ_HZ(1000000), .BAUD_RATE(100000),
        .MIN_GAP_CYCLES(3000), .HEARTBEAT_CYCLES(6000)) dut(
        .clk(clk), .rst(rst), .scene_id(scene), .requested_scene_id(requested),
        .last_event_scene(last_scene), .request_pending(pending),
        .latency_valid(latency_valid), .request_count(requests),
        .ignored_count(ignored), .commit_count(commits), .latency_cycles(latency), .tx(tx)
    );
    always #5 clk=~clk;
    task read_byte;
        output [7:0] data;
        integer b;
        begin
            @(negedge tx); repeat(5) @(posedge clk); #1;
            if(tx!==0) $fatal(1,"Bad UART start bit");
            for(b=0;b<8;b=b+1) begin
                repeat(10) @(posedge clk); #1; data[b]=tx;
            end
            repeat(10) @(posedge clk); #1;
            if(tx!==1) $fatal(1,"Bad UART stop bit");
        end
    endtask
    initial begin
        repeat(4) @(negedge clk); rst=0;
        for(packet=0;packet<3;packet=packet+1) begin
            for(i=0;i<24;i=i+1) begin
                read_byte(bytes[i]);
                // Change live state inside packet 1. Packet must remain coherent.
                if(packet==0 && i==4) begin scene=1; requests=32'h76543210; latency=25; end
            end
            checksum=0;
            for(i=0;i<24;i=i+1) checksum=checksum ^ bytes[i];
            if (checksum!==0 || bytes[0]!==8'ha5 || bytes[1]!==8'h33 || bytes[2]!==1 ||
                bytes[4]!==2 || bytes[5]!==2 || bytes[10]!==9 || bytes[14]!==11 || bytes[22]!==2)
                $fatal(1,"UART header, flags, fields or checksum mismatch");
            if(packet==0) begin
                if(bytes[3]!==2 || {bytes[9],bytes[8],bytes[7],bytes[6]}!==32'h12345678 ||
                    {bytes[21],bytes[20],bytes[19],bytes[18]}!==32'h00abcdef)
                    $fatal(1,"Snapshot changed while transmitting");
            end else if(bytes[3]!==1 || {bytes[9],bytes[8],bytes[7],bytes[6]}!==32'h76543210 ||
                {bytes[21],bytes[20],bytes[19],bytes[18]}!==25)
                $fatal(1,"New state or unchanged heartbeat missing");
        end
        $display("PASS: three complete 24-byte UART packets; 8N1 timing, coherent snapshot, change update, heartbeat, little-endian counters and XOR");
        $finish;
    end
    initial begin #250000; $fatal(1,"UART test timeout"); end
endmodule
