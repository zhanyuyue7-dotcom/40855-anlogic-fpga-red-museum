`timescale 1ns/1ps
module audio_count_equivalence_tb;
    reg clk=0, rst=1, enable=0, init_done=0;
    wire sd_req;
    wire [31:0] sd_addr;
    reg [7:0] sd_data=0;
    reg sd_valid=0, sd_end=0;
    wire fifo_we;
    wire [31:0] fifo_data;
    reg fifo_full=0;
    reg fifo_almost_full=0;
    wire present;
    integer sector_byte=0;
    integer phase=0;
    reg [7:0] header [0:511];

    audio_pcm_raw_reader #(.AUDIO_START_SECTOR(100), .SONG_COUNT(3)) dut(
        .clk(clk), .rst(rst), .enable(enable), .sd_init_done(init_done),
        .sd_sec_read(sd_req), .sd_sec_read_addr(sd_addr),
        .sd_sec_read_data(sd_data), .sd_sec_read_data_valid(sd_valid),
        .sd_sec_read_end(sd_end), .fifo_wr_en(fifo_we), .fifo_wr_data(fifo_data),
        .fifo_full(fifo_full), .fifo_almost_full(fifo_almost_full),
        .stream_present(present)
    );

    wire ref_req,ref_we,ref_present;
    wire [31:0] ref_addr,ref_data;
    integer writes=0;
    audio_pcm_raw_reader_ref #(.AUDIO_START_SECTOR(100), .SONG_COUNT(3)) reference_dut(
        .clk(clk), .rst(rst), .enable(enable), .sd_init_done(init_done),
        .sd_sec_read(ref_req), .sd_sec_read_addr(ref_addr),
        .sd_sec_read_data(sd_data), .sd_sec_read_data_valid(sd_valid),
        .sd_sec_read_end(sd_end), .fifo_wr_en(ref_we), .fifo_wr_data(ref_data),
        .fifo_full(fifo_full), .fifo_almost_full(fifo_almost_full),
        .stream_present(ref_present)
    );

    always @(negedge clk) if(!rst) begin
        if ({sd_req,sd_addr,fifo_we,present} !== {ref_req,ref_addr,ref_we,ref_present})
            $fatal(1,"audio interface divergence at write %0d",writes);
        if(fifo_we) begin
            if(fifo_data!==ref_data)$fatal(1,"audio data divergence");
            writes=writes+1;
        end
        if(dut.song_empty !== (dut.song_remaining==0))
            $fatal(1,"zero flags mismatch count=%h flags=%b",dut.song_remaining,dut.remaining_zero_bytes);
    end
    always #5 clk=~clk;

    integer i;
    initial begin
        for(i=0;i<512;i=i+1) header[i]=0;
        header[0]="A"; header[1]="U"; header[2]="D"; header[3]="P";
        header[4]=1; header[5]=3;
        header[8]=1; header[12]=4; header[14]=1;       // song 0: sector +1, one frame
        header[16]=130; header[20]=4; header[21]=1;
        header[24]=132; header[28]=0;
        repeat(4) @(negedge clk); rst=0; init_done=1; enable=1;
        wait(writes>=16600);
        $display("PASS audio cycle equivalence: 16-bit/8-bit borrow, zero-length song, wraparound, 16600 PCM words");
        $finish;
    end

    always @(posedge clk) begin
        sd_valid <= 1'b0;
        sd_end <= 1'b0;
        if (sd_req && phase==0) begin
            phase <= 1;
            sector_byte <= 0;
        end
        if (phase==1) begin
            sd_valid <= 1'b1;
            if (sd_addr==100) sd_data <= header[sector_byte];
            else if (sector_byte==0) sd_data <= 8'h11;
            else if (sector_byte==1) sd_data <= 8'h22;
            else if (sector_byte==2) sd_data <= 8'h33;
            else if (sector_byte==3) sd_data <= 8'h44;
            else sd_data <= 8'h00;
            if (sector_byte==511) begin
                sd_end <= 1'b1;
                phase <= 0;
            end else sector_byte <= sector_byte + 1;
        end
    end

    initial begin #10000000; $fatal(1,"audio reader timeout"); end
endmodule
