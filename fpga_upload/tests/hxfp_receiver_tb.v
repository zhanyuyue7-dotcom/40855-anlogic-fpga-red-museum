`timescale 1ns/1ps
module hxfp_receiver_tb;
    reg clk=0, rst=1;
    always #5 clk=~clk;
    wire rx_ready;
    reg rx_start=0,rx_valid=0,rx_end=0;
    reg [7:0] rx_data=0;
    reg [47:0] rx_peer=0;
    wire tx_valid,tx_last;
    reg tx_ready=0;
    wire [7:0] tx_data;
    wire [47:0] tx_peer;
    wire frame_begin,pixel_valid,frame_commit,frame_abort,active;
    wire [31:0] pixel_addr,received,displayed;
    wire [15:0] pixel;
    reg frame_begin_ready=0,pixel_ready=0,commit_ready=0;
    reg frame_error=0;
    wire [31:0] rgb888;
    reg [7:0] vectors[0:2000000];
    reg [47:0] golden[0:700000];
    reg [7:0] ack[0:35];
    integer count=0, pixel_count=0, cycle=0, commit_wait=0;
    integer fd,bytes,cursor=0,n,expected_length,flags,expected_writes,expected_display;
    integer response_at,timeout,packet_count=0;
    reg [47:0] expected_peer;
    reg [1023:0] vector_path,golden_path;

    hxfp_receiver #(.TIMEOUT_CYCLES(20000)) dut(
        .clk(clk),.rst(rst),.rx_ready(rx_ready),.rx_start(rx_start),.rx_valid(rx_valid),
        .rx_data(rx_data),.rx_end(rx_end),.rx_peer(rx_peer),
        .tx_valid(tx_valid),.tx_ready(tx_ready),.tx_data(tx_data),.tx_last(tx_last),.tx_peer(tx_peer),
        .frame_begin(frame_begin),.frame_begin_ready(frame_begin_ready),
        .pixel_valid(pixel_valid),.pixel_ready(pixel_ready),.pixel_address(pixel_addr),.pixel_rgb565(pixel),
        .frame_commit(frame_commit),.frame_commit_ready(commit_ready),.frame_abort(frame_abort),
        .frame_error(frame_error),.transfer_active(active),.received_bytes(received),.displayed_frames(displayed));
    hxfp_rgb565_expand expand(.rgb565(pixel),.rgb888_word(rgb888));

    always @(negedge clk) begin
        cycle=cycle+1;
        frame_begin_ready=(cycle%7==0);
        pixel_ready=(cycle%5!=0 && cycle%11!=0);
        tx_ready=(cycle%3!=0);
        if (frame_commit) commit_wait=commit_wait+1;
        else commit_wait=0;
        commit_ready=commit_wait>=43;
    end
    always @(posedge clk) if (!rst) begin
        if (pixel_valid && pixel_ready) begin
            if ({pixel_addr,pixel} !== golden[pixel_count])
                $fatal(1,"pixel mismatch at write %0d: addr=%0d value=%h expected=%h",pixel_count,pixel_addr,pixel,golden[pixel_count]);
            if (rgb888 !== {8'd0,pixel[15:11],pixel[15:13],pixel[10:5],pixel[10:9],pixel[4:0],pixel[4:2]})
                $fatal(1,"RGB expansion mismatch");
            pixel_count=pixel_count+1;
        end
        if (tx_valid && tx_ready) begin
            if (count>=36) $fatal(1,"long ACK");
            ack[count]=tx_data;
            if (tx_last != (count==35)) $fatal(1,"bad tx_last");
            if (tx_peer!==expected_peer) $fatal(1,"wrong ACK peer");
            count=count+1;
        end
        if (frame_commit && !commit_ready && tx_valid) $fatal(1,"premature display ACK");
    end

    initial begin
        if (!$value$plusargs("vectors=%s",vector_path)) $fatal(1,"no vectors");
        if (!$value$plusargs("golden=%s",golden_path)) $fatal(1,"no golden");
        fd=$fopen(vector_path,"rb"); bytes=$fread(vectors,fd); $fclose(fd);
        $readmemh(golden_path,golden);
        repeat(5) @(negedge clk);
        rst=0;
        while (cursor<bytes) begin
            n={vectors[cursor],vectors[cursor+1]};
            expected_length=vectors[cursor+2]; flags=vectors[cursor+3];
            expected_peer={vectors[cursor+4],vectors[cursor+5],vectors[cursor+6],vectors[cursor+7],vectors[cursor+8],vectors[cursor+9]};
            expected_writes={vectors[cursor+10],vectors[cursor+11],vectors[cursor+12],vectors[cursor+13]};
            expected_display={vectors[cursor+14],vectors[cursor+15],vectors[cursor+16],vectors[cursor+17]};
            cursor=cursor+18;
            wait(rx_ready);
            @(negedge clk); count=0;
            if (flags==1) begin
                repeat(20010) @(negedge clk);
            end else begin
                rx_peer=expected_peer; rx_start=1;
                @(negedge clk); rx_start=0;
                for (integer j=0;j<n;j=j+1) begin
                    rx_valid=1;rx_data=vectors[cursor+j];
                    @(negedge clk);
                end
                rx_valid=0;
                @(negedge clk);rx_end=1;
                @(negedge clk);rx_end=0;
            end
            cursor=cursor+n;
            response_at=cursor;
            timeout=0;
            if (expected_length!=0) begin
                while (count<expected_length && timeout<19000) begin
                    @(negedge clk); timeout=timeout+1;
                end
                if (count!=expected_length) $fatal(1,"response timeout case=%0d count=%0d",packet_count,count);
                for (integer j=0;j<expected_length;j=j+1)
                    if (ack[j]!==vectors[response_at+j])
                        $fatal(1,"ACK mismatch case=%0d byte=%0d actual=%h expected=%h",packet_count,j,ack[j],vectors[response_at+j]);
            end else repeat(200) @(negedge clk);
            cursor=cursor+expected_length;
            if (count!=expected_length) $fatal(1,"unexpected ACK");
            if (pixel_count!=expected_writes) $fatal(1,"unexpected write count case=%0d got=%0d want=%0d",packet_count,pixel_count,expected_writes);
            if (displayed!=expected_display) $fatal(1,"unexpected commit count case=%0d",packet_count);
            packet_count=packet_count+1;
            if (packet_count%100==0) begin
                $display("HXFP progress: %0d scenarios, %0d pixels",packet_count,pixel_count);
                $fflush();
            end
        end
        $display("PASS HXFP RTL: %0d packet scenarios, %0d pixels checked, %0d display commits",packet_count,pixel_count,displayed);
        $finish;
    end
    initial begin #500000000; $fatal(1,"global simulation timeout"); end
endmodule
