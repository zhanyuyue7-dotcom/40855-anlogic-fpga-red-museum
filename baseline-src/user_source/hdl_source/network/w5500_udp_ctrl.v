// W5500 controller for the Socket 0 UDP command endpoint.
// The INT pin is the fast wake-up path; the bounded poll counter remains as a
// recovery path when a module or cable drops an interrupt edge.
module w5500_udp_ctrl #(
    parameter integer RESET_CYCLES      = 25_000,
    parameter integer POST_RESET_CYCLES = 500_000,
    parameter integer POLL_CYCLES       = 1_000,
    parameter [31:0] GATEWAY_IP         = 32'hc0a8_0001,
    parameter [31:0] SUBNET_MASK        = 32'hffff_ff00,
    parameter [47:0] LOCAL_MAC          = 48'h02_55_00_00_00_01,
    parameter [31:0] LOCAL_IP           = 32'hc0a8_0014,
    parameter [15:0] LOCAL_PORT         = 16'd5000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        w5500_int_n,
    output reg         w5500_rst_n,

    output reg         xfer_start,
    output reg         xfer_write,
    output reg [15:0]  xfer_addr,
    output reg [4:0]   xfer_block,
    output reg [7:0]   xfer_wdata,
    input  wire        xfer_done,
    input  wire [7:0]  xfer_rdata,

    output reg         rx_packet_start,
    output reg         rx_data_valid,
    output reg [7:0]   rx_data,
    output reg         rx_packet_done,
    output reg         link_up,
    output reg         init_done,
    output reg         init_error,
    output reg [7:0]   version
);
    localparam [7:0] ST_RESET       = 8'd0;
    localparam [7:0] ST_POST_RESET  = 8'd1;
    localparam [7:0] ST_VER_ISSUE   = 8'd2;
    localparam [7:0] ST_VER_WAIT    = 8'd3;
    localparam [7:0] ST_CFG_ISSUE   = 8'd4;
    localparam [7:0] ST_CFG_WAIT    = 8'd5;
    localparam [7:0] ST_CR_ISSUE    = 8'd6;
    localparam [7:0] ST_CR_WAIT     = 8'd7;
    localparam [7:0] ST_SR_ISSUE    = 8'd8;
    localparam [7:0] ST_SR_WAIT     = 8'd9;
    localparam [7:0] ST_PHY_ISSUE   = 8'd10;
    localparam [7:0] ST_PHY_WAIT    = 8'd11;
    localparam [7:0] ST_POLL_DELAY  = 8'd12;
    localparam [7:0] ST_RSR_H_ISSUE = 8'd13;
    localparam [7:0] ST_RSR_H_WAIT  = 8'd14;
    localparam [7:0] ST_RSR_L_ISSUE = 8'd15;
    localparam [7:0] ST_RSR_L_WAIT  = 8'd16;
    localparam [7:0] ST_RD_H_ISSUE  = 8'd17;
    localparam [7:0] ST_RD_H_WAIT   = 8'd18;
    localparam [7:0] ST_RD_L_ISSUE  = 8'd19;
    localparam [7:0] ST_RD_L_WAIT   = 8'd20;
    localparam [7:0] ST_HDR_ISSUE   = 8'd21;
    localparam [7:0] ST_HDR_WAIT    = 8'd22;
    localparam [7:0] ST_PAY_ISSUE   = 8'd23;
    localparam [7:0] ST_PAY_WAIT    = 8'd24;
    localparam [7:0] ST_RXRD_H_ISSUE= 8'd25;
    localparam [7:0] ST_RXRD_H_WAIT = 8'd26;
    localparam [7:0] ST_RXRD_L_ISSUE= 8'd27;
    localparam [7:0] ST_RXRD_L_WAIT = 8'd28;
    localparam [7:0] ST_RECV_ISSUE  = 8'd29;
    localparam [7:0] ST_RECV_WAIT   = 8'd30;
    localparam [7:0] ST_ERROR       = 8'd31;

    reg [7:0]  state;
    reg [31:0] delay_count;
    reg [5:0]  cfg_index;
    reg [7:0]  rx_rsr_hi;
    reg [15:0] rx_size;
    reg [7:0]  rx_rd_hi;
    reg [15:0] rx_rd;
    reg [3:0]  header_index;
    reg [7:0]  header [0:7];
    reg [15:0] payload_len;
    reg [15:0] payload_index;
    reg [15:0] next_rx_rd;
    (* async_reg = "true" *) reg [1:0] w5500_int_sync;
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= ST_RESET;
            delay_count      <= 32'd0;
            cfg_index        <= 6'd0;
            w5500_rst_n      <= 1'b0;
            xfer_start       <= 1'b0;
            xfer_write       <= 1'b0;
            xfer_addr        <= 16'd0;
            xfer_block       <= 5'd0;
            xfer_wdata       <= 8'd0;
            rx_packet_start  <= 1'b0;
            rx_data_valid    <= 1'b0;
            rx_data          <= 8'd0;
            rx_packet_done   <= 1'b0;
            link_up          <= 1'b0;
            init_done        <= 1'b0;
            init_error       <= 1'b0;
            version          <= 8'd0;
            rx_rsr_hi        <= 8'd0;
            rx_size          <= 16'd0;
            rx_rd_hi         <= 8'd0;
            rx_rd            <= 16'd0;
            header_index     <= 4'd0;
            payload_len      <= 16'd0;
            payload_index    <= 16'd0;
            next_rx_rd       <= 16'd0;
            w5500_int_sync   <= 2'b11;
            for (i = 0; i < 8; i = i + 1)
                header[i] <= 8'd0;
        end else begin
            w5500_int_sync <= {w5500_int_sync[0], w5500_int_n};
            xfer_start      <= 1'b0;
            rx_packet_start <= 1'b0;
            rx_data_valid   <= 1'b0;
            rx_packet_done  <= 1'b0;

            case (state)
                ST_RESET: begin
                    w5500_rst_n <= 1'b0;
                    if (delay_count >= RESET_CYCLES-1) begin
                        delay_count <= 32'd0;
                        w5500_rst_n <= 1'b1;
                        state       <= ST_POST_RESET;
                    end else begin
                        delay_count <= delay_count + 1'b1;
                    end
                end

                ST_POST_RESET: begin
                    if (delay_count >= POST_RESET_CYCLES-1) begin
                        delay_count <= 32'd0;
                        state       <= ST_VER_ISSUE;
                    end else begin
                        delay_count <= delay_count + 1'b1;
                    end
                end

                ST_VER_ISSUE: begin
                    xfer_write <= 1'b0;
                    xfer_addr  <= 16'h0039;
                    xfer_block <= 5'h00;
                    xfer_start <= 1'b1;
                    state      <= ST_VER_WAIT;
                end

                ST_VER_WAIT: begin
                    if (xfer_done) begin
                        version <= xfer_rdata;
                        if (xfer_rdata == 8'h04) begin
                            cfg_index <= 6'd0;
                            state     <= ST_CFG_ISSUE;
                        end else begin
                            init_error <= 1'b1;
                            state      <= ST_ERROR;
                        end
                    end
                end

                ST_CFG_ISSUE: begin
                    xfer_write <= 1'b1;
                    xfer_block <= 5'h00;
                    case (cfg_index)
                        6'd0:  begin xfer_addr <= 16'h0001; xfer_wdata <= GATEWAY_IP[31:24]; end
                        6'd1:  begin xfer_addr <= 16'h0002; xfer_wdata <= GATEWAY_IP[23:16]; end
                        6'd2:  begin xfer_addr <= 16'h0003; xfer_wdata <= GATEWAY_IP[15:8];  end
                        6'd3:  begin xfer_addr <= 16'h0004; xfer_wdata <= GATEWAY_IP[7:0];   end
                        6'd4:  begin xfer_addr <= 16'h0005; xfer_wdata <= SUBNET_MASK[31:24]; end
                        6'd5:  begin xfer_addr <= 16'h0006; xfer_wdata <= SUBNET_MASK[23:16]; end
                        6'd6:  begin xfer_addr <= 16'h0007; xfer_wdata <= SUBNET_MASK[15:8];  end
                        6'd7:  begin xfer_addr <= 16'h0008; xfer_wdata <= SUBNET_MASK[7:0];   end
                        6'd8:  begin xfer_addr <= 16'h0009; xfer_wdata <= LOCAL_MAC[47:40]; end
                        6'd9:  begin xfer_addr <= 16'h000a; xfer_wdata <= LOCAL_MAC[39:32]; end
                        6'd10: begin xfer_addr <= 16'h000b; xfer_wdata <= LOCAL_MAC[31:24]; end
                        6'd11: begin xfer_addr <= 16'h000c; xfer_wdata <= LOCAL_MAC[23:16]; end
                        6'd12: begin xfer_addr <= 16'h000d; xfer_wdata <= LOCAL_MAC[15:8];  end
                        6'd13: begin xfer_addr <= 16'h000e; xfer_wdata <= LOCAL_MAC[7:0];   end
                        6'd14: begin xfer_addr <= 16'h000f; xfer_wdata <= LOCAL_IP[31:24]; end
                        6'd15: begin xfer_addr <= 16'h0010; xfer_wdata <= LOCAL_IP[23:16]; end
                        6'd16: begin xfer_addr <= 16'h0011; xfer_wdata <= LOCAL_IP[15:8];  end
                        6'd17: begin xfer_addr <= 16'h0012; xfer_wdata <= LOCAL_IP[7:0];   end
                        6'd18: begin xfer_addr <= 16'h0019; xfer_wdata <= 8'h07; end
                        6'd19: begin xfer_addr <= 16'h001a; xfer_wdata <= 8'hd0; end
                        6'd20: begin xfer_addr <= 16'h001e; xfer_block <= 5'h01; xfer_wdata <= 8'h02; end
                        6'd21: begin xfer_addr <= 16'h001f; xfer_block <= 5'h01; xfer_wdata <= 8'h02; end
                        6'd22: begin xfer_addr <= 16'h0004; xfer_block <= 5'h01; xfer_wdata <= LOCAL_PORT[15:8]; end
                        6'd23: begin xfer_addr <= 16'h0005; xfer_block <= 5'h01; xfer_wdata <= LOCAL_PORT[7:0]; end
                        6'd24: begin xfer_addr <= 16'h0000; xfer_block <= 5'h01; xfer_wdata <= 8'h02; end
                        // Enable Socket 0 receive interrupt in the common mask
                        // and the per-socket mask. The poll counter below still
                        // provides a bounded fallback if INT is missed.
                        6'd25: begin xfer_addr <= 16'h0018; xfer_block <= 5'h00; xfer_wdata <= 8'h01; end
                        6'd26: begin xfer_addr <= 16'h002c; xfer_block <= 5'h01; xfer_wdata <= 8'h04; end
                        default: begin xfer_addr <= 16'h0001; xfer_block <= 5'h01; xfer_wdata <= 8'h01; end
                    endcase
                    xfer_start <= 1'b1;
                    state      <= ST_CFG_WAIT;
                end

                ST_CFG_WAIT: begin
                    if (xfer_done) begin
                        if (cfg_index == 6'd27)
                            state <= ST_CR_ISSUE;
                        else begin
                            cfg_index <= cfg_index + 1'b1;
                            state     <= ST_CFG_ISSUE;
                        end
                    end
                end

                ST_CR_ISSUE: begin
                    xfer_write <= 1'b0; xfer_addr <= 16'h0001; xfer_block <= 5'h01;
                    xfer_start <= 1'b1; state <= ST_CR_WAIT;
                end
                ST_CR_WAIT: begin
                    if (xfer_done) begin
                        if (xfer_rdata == 8'h00) state <= ST_SR_ISSUE;
                        else state <= ST_CR_ISSUE;
                    end
                end

                ST_SR_ISSUE: begin
                    xfer_write <= 1'b0; xfer_addr <= 16'h0003; xfer_block <= 5'h01;
                    xfer_start <= 1'b1; state <= ST_SR_WAIT;
                end
                ST_SR_WAIT: begin
                    if (xfer_done) begin
                        if (xfer_rdata == 8'h22) state <= ST_PHY_ISSUE;
                        else state <= ST_SR_ISSUE;
                    end
                end

                ST_PHY_ISSUE: begin
                    xfer_write <= 1'b0; xfer_addr <= 16'h002e; xfer_block <= 5'h00;
                    xfer_start <= 1'b1; state <= ST_PHY_WAIT;
                end
                ST_PHY_WAIT: begin
                    if (xfer_done) begin
                        link_up   <= xfer_rdata[0];
                        init_done <= xfer_rdata[0];
                        if (xfer_rdata[0]) state <= ST_POLL_DELAY;
                        else state <= ST_PHY_ISSUE;
                    end
                end

                ST_POLL_DELAY: begin
                    // INT is active low. Wake as soon as the synchronized edge
                    // arrives; otherwise retain the old periodic poll budget.
                    if (!w5500_int_sync[1] || delay_count >= POLL_CYCLES-1) begin
                        delay_count <= 32'd0;
                        state <= ST_RSR_H_ISSUE;
                    end else begin
                        delay_count <= delay_count + 1'b1;
                    end
                end

                ST_RSR_H_ISSUE: begin
                    xfer_write <= 1'b0; xfer_addr <= 16'h0026; xfer_block <= 5'h01;
                    xfer_start <= 1'b1; state <= ST_RSR_H_WAIT;
                end
                ST_RSR_H_WAIT: begin
                    if (xfer_done) begin
                        rx_rsr_hi <= xfer_rdata;
                        state <= ST_RSR_L_ISSUE;
                    end
                end
                ST_RSR_L_ISSUE: begin
                    xfer_write <= 1'b0; xfer_addr <= 16'h0027; xfer_block <= 5'h01;
                    xfer_start <= 1'b1; state <= ST_RSR_L_WAIT;
                end
                ST_RSR_L_WAIT: begin
                    if (xfer_done) begin
                        rx_size <= {rx_rsr_hi, xfer_rdata};
                        if ({rx_rsr_hi, xfer_rdata} != 16'd0)
                            state <= ST_RD_H_ISSUE;
                        else
                            state <= ST_POLL_DELAY;
                    end
                end

                ST_RD_H_ISSUE: begin
                    xfer_write <= 1'b0; xfer_addr <= 16'h0028; xfer_block <= 5'h01;
                    xfer_start <= 1'b1; state <= ST_RD_H_WAIT;
                end
                ST_RD_H_WAIT: begin
                    if (xfer_done) begin
                        rx_rd_hi <= xfer_rdata;
                        state <= ST_RD_L_ISSUE;
                    end
                end
                ST_RD_L_ISSUE: begin
                    xfer_write <= 1'b0; xfer_addr <= 16'h0029; xfer_block <= 5'h01;
                    xfer_start <= 1'b1; state <= ST_RD_L_WAIT;
                end
                ST_RD_L_WAIT: begin
                    if (xfer_done) begin
                        rx_rd <= {rx_rd_hi, xfer_rdata};
                        header_index <= 4'd0;
                        state <= ST_HDR_ISSUE;
                    end
                end

                ST_HDR_ISSUE: begin
                    xfer_write <= 1'b0;
                    xfer_addr  <= rx_rd + header_index;
                    xfer_block <= 5'h03;
                    xfer_start <= 1'b1;
                    state      <= ST_HDR_WAIT;
                end
                ST_HDR_WAIT: begin
                    if (xfer_done) begin
                        header[header_index] <= xfer_rdata;
                        if (header_index == 4'd7) begin
                            payload_len   <= {header[6], xfer_rdata};
                            payload_index <= 16'd0;
                            if (rx_size < (16'd8 + {header[6], xfer_rdata})) begin
                                state <= ST_POLL_DELAY;
                            end else if ({header[6], xfer_rdata} == 16'd8) begin
                                rx_packet_start <= 1'b1;
                                state <= ST_PAY_ISSUE;
                            end else begin
                                next_rx_rd <= rx_rd + 16'd8 + {header[6], xfer_rdata};
                                state <= ST_RXRD_H_ISSUE;
                            end
                        end else begin
                            header_index <= header_index + 1'b1;
                            state <= ST_HDR_ISSUE;
                        end
                    end
                end

                ST_PAY_ISSUE: begin
                    xfer_write <= 1'b0;
                    xfer_addr  <= rx_rd + 16'd8 + payload_index;
                    xfer_block <= 5'h03;
                    xfer_start <= 1'b1;
                    state      <= ST_PAY_WAIT;
                end
                ST_PAY_WAIT: begin
                    if (xfer_done) begin
                        if (payload_index < 16'd8) begin
                            rx_data       <= xfer_rdata;
                            rx_data_valid <= 1'b1;
                        end
                        if (payload_index + 1'b1 >= payload_len) begin
                            next_rx_rd <= rx_rd + 16'd8 + payload_len;
                            state <= ST_RXRD_H_ISSUE;
                        end else begin
                            payload_index <= payload_index + 1'b1;
                            state <= ST_PAY_ISSUE;
                        end
                    end
                end

                ST_RXRD_H_ISSUE: begin
                    xfer_write <= 1'b1; xfer_addr <= 16'h0028; xfer_block <= 5'h01;
                    xfer_wdata <= next_rx_rd[15:8]; xfer_start <= 1'b1; state <= ST_RXRD_H_WAIT;
                end
                ST_RXRD_H_WAIT: begin
                    if (xfer_done) state <= ST_RXRD_L_ISSUE;
                end
                ST_RXRD_L_ISSUE: begin
                    xfer_write <= 1'b1; xfer_addr <= 16'h0029; xfer_block <= 5'h01;
                    xfer_wdata <= next_rx_rd[7:0]; xfer_start <= 1'b1; state <= ST_RXRD_L_WAIT;
                end
                ST_RXRD_L_WAIT: begin
                    if (xfer_done) begin
                        rx_packet_done <= 1'b1;
                        state <= ST_RECV_ISSUE;
                    end
                end
                ST_RECV_ISSUE: begin
                    xfer_write <= 1'b1; xfer_addr <= 16'h0001; xfer_block <= 5'h01;
                    xfer_wdata <= 8'h40; xfer_start <= 1'b1; state <= ST_RECV_WAIT;
                end
                ST_RECV_WAIT: begin
                    if (xfer_done) state <= ST_POLL_DELAY;
                end
                ST_ERROR: begin
                    w5500_rst_n <= 1'b1;
                    link_up     <= 1'b0;
                    init_done   <= 1'b0;
                end
                default: state <= ST_RESET;
            endcase
        end
    end
endmodule
