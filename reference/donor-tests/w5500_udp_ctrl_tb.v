`timescale 1ns / 1ps

module w5500_udp_ctrl_tb;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    wire w5500_rst_n;
    wire xfer_start;
    wire xfer_write;
    wire [15:0] xfer_addr;
    wire [4:0] xfer_block;
    wire [7:0] xfer_wdata;
    reg xfer_done = 1'b0;
    reg [7:0] xfer_rdata = 8'd0;
    wire packet_start;
    wire data_valid;
    wire [7:0] data;
    wire packet_done;
    wire link_up;
    wire init_done;
    wire init_error;
    wire [7:0] version;
    wire cmd_next;
    wire command_valid;
    wire command_error;
    wire [7:0] command_seq;

    reg pending;
    reg pending_write;
    reg [15:0] pending_addr;
    reg [4:0] pending_block;
    reg [7:0] pending_wdata;
    integer init_write_count;
    integer recv_command_count;
    reg [7:0] udp_bytes [0:15];
    reg [55:0] first_seven;
    integer i;

    always #10 clk = ~clk;

    w5500_udp_ctrl #(
        .RESET_CYCLES(4), .POST_RESET_CYCLES(4), .POLL_CYCLES(3),
        .GATEWAY_IP(32'hac16_73fe), .SUBNET_MASK(32'hffff_ff00),
        .LOCAL_MAC(48'h02_55_00_00_00_01), .LOCAL_IP(32'hac16_734f),
        .LOCAL_PORT(16'd5000)
    ) dut (
        .clk(clk), .rst_n(rst_n), .w5500_int_n(1'b1), .w5500_rst_n(w5500_rst_n),
        .xfer_start(xfer_start), .xfer_write(xfer_write), .xfer_addr(xfer_addr),
        .xfer_block(xfer_block), .xfer_wdata(xfer_wdata),
        .xfer_done(xfer_done), .xfer_rdata(xfer_rdata),
        .rx_packet_start(packet_start), .rx_data_valid(data_valid), .rx_data(data),
        .rx_packet_done(packet_done), .link_up(link_up), .init_done(init_done),
        .init_error(init_error), .version(version)
    );

    w5500_command_decoder decoder (
        .clk(clk), .rst(!rst_n), .packet_start(packet_start),
        .data_valid(data_valid), .data(data),
        .cmd_next(cmd_next), .cmd_auto_toggle(), .cmd_notice(), .cmd_clear(),
        .cmd_brightness_up(), .cmd_brightness_down(),
        .command_valid(command_valid), .command_error(command_error),
        .command_seq(command_seq)
    );

    function automatic [7:0] crc8;
        input [55:0] bytes;
        integer b;
        integer k;
        reg [7:0] c;
        reg [7:0] d;
        begin
            c = 0;
            for (b = 6; b >= 0; b = b - 1) begin
                d = bytes[b*8 +: 8];
                c = c ^ d;
                for (k = 0; k < 8; k = k + 1)
                    c = c[7] ? ((c << 1) ^ 8'h07) : (c << 1);
            end
            crc8 = c;
        end
    endfunction

    function automatic [7:0] mock_read;
        input [4:0] block;
        input [15:0] address;
        begin
            if ((block == 0) && (address == 16'h0039))
                mock_read = 8'h04;
            else if ((block == 0) && (address == 16'h002e))
                mock_read = 8'h01;
            else if ((block == 1) && (address == 16'h0001))
                mock_read = 8'h00;
            else if ((block == 1) && (address == 16'h0003))
                mock_read = 8'h22;
            else if ((block == 1) && (address == 16'h0026))
                mock_read = 8'h00;
            else if ((block == 1) && (address == 16'h0027))
                mock_read = 8'h10;
            else if ((block == 1) && ((address == 16'h0028) || (address == 16'h0029)))
                mock_read = 8'h00;
            else if ((block == 3) && (address < 16))
                mock_read = udp_bytes[address];
            else
                mock_read = 8'h00;
        end
    endfunction

    always @(posedge clk) begin
        xfer_done <= 1'b0;
        if (pending) begin
            xfer_done  <= 1'b1;
            xfer_rdata <= pending_write ? 8'h00 : mock_read(pending_block, pending_addr);
            if (pending_write) begin
                if ((pending_block == 1) && (pending_addr == 16'h0001) && (pending_wdata == 8'h40))
                    recv_command_count <= recv_command_count + 1;
                else
                    init_write_count <= init_write_count + 1;
            end
            pending <= 1'b0;
        end
        if (xfer_start) begin
            pending       <= 1'b1;
            pending_write <= xfer_write;
            pending_addr  <= xfer_addr;
            pending_block <= xfer_block;
            pending_wdata <= xfer_wdata;
        end
    end

    initial begin
        pending = 0;
        init_write_count = 0;
        recv_command_count = 0;
        udp_bytes[0] = 8'hc0;
        udp_bytes[1] = 8'ha8;
        udp_bytes[2] = 8'h32;
        udp_bytes[3] = 8'h0a;
        udp_bytes[4] = 8'h17;
        udp_bytes[5] = 8'h70;
        udp_bytes[6] = 8'h00;
        udp_bytes[7] = 8'h08;
        udp_bytes[8] = 8'ha5;
        udp_bytes[9] = 8'h01;
        udp_bytes[10] = 8'h2a;
        udp_bytes[11] = 8'h10;
        udp_bytes[12] = 8'h00;
        udp_bytes[13] = 8'h00;
        udp_bytes[14] = 8'h00;
        first_seven = {udp_bytes[8], udp_bytes[9], udp_bytes[10], udp_bytes[11],
                       udp_bytes[12], udp_bytes[13], udp_bytes[14]};
        udp_bytes[15] = crc8(first_seven);

        repeat (4) @(posedge clk);
        rst_n <= 1'b1;

        wait(command_valid);
        if (!cmd_next || command_seq !== 8'h2a || command_error) begin
            $display("FAIL: UDP payload was not decoded seq=%02x next=%b error=%b",
                     command_seq, cmd_next, command_error);
            $fatal(1);
        end
        if (!init_done || !link_up || init_error || version !== 8'h04) begin
            $display("FAIL: init state done=%b link=%b error=%b version=%02x",
                     init_done, link_up, init_error, version);
            $fatal(1);
        end
        if (init_write_count < 26) begin
            $display("FAIL: incomplete configuration writes=%0d", init_write_count);
            $fatal(1);
        end
        wait(packet_done);
        wait(recv_command_count == 1);
        $display("PASS: W5500 init, UDP header stripping and command delivery");
        $finish;
    end

    initial begin
        #1000000;
        $display("FAIL: timeout");
        $fatal(1);
    end
endmodule
