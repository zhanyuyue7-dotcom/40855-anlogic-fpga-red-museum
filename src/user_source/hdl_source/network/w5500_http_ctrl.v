// Small TCP/HTTP server for the FPGA-hosted control page.
// Socket 1 is a TCP listener on port 80. The page is a fixed ROM response;
// command URLs are short and map to the existing validated control paths.
module w5500_http_ctrl #(
    parameter integer PAGE_RESPONSE_LEN = 2071,
    parameter integer CMD_RESPONSE_LEN  = 88,
    parameter integer POLL_CYCLES        = 2_000,
    parameter WEB_INIT_FILE = "w5500_web_response.hex"
)(
    input  wire        clk,
    input  wire        rst_n,
    output reg         xfer_start,
    output reg         xfer_write,
    output reg  [15:0] xfer_addr,
    output reg  [4:0]  xfer_block,
    output reg  [7:0]  xfer_wdata,
    input  wire        xfer_done,
    input  wire [7:0]  xfer_rdata,
    output reg         burst_start,
    output reg         burst_write,
    output reg  [15:0] burst_addr,
    output reg  [4:0]  burst_block,
    output reg  [7:0]  burst_len,
    output reg         burst_tx_valid,
    output reg  [7:0]  burst_tx_data,
    input  wire        burst_tx_ready,
    input  wire        burst_done,
    output reg         cmd_next,
    output reg         cmd_auto_toggle,
    output reg         cmd_notice,
    output reg         cmd_emergency,
    output reg         cmd_clear,
    output reg         cmd_brightness_up,
    output reg         cmd_brightness_down,
    output reg         cmd_audio_toggle,
    output reg         cmd_ui_toggle
);
    localparam [7:0] ST_CFG_ISSUE   = 8'd0;
    localparam [7:0] ST_CFG_WAIT    = 8'd1;
    localparam [7:0] ST_OPEN_ISSUE  = 8'd2;
    localparam [7:0] ST_OPEN_WAIT   = 8'd3;
    localparam [7:0] ST_SR_ISSUE    = 8'd4;
    localparam [7:0] ST_SR_WAIT     = 8'd5;
    localparam [7:0] ST_LISTEN_ISSUE= 8'd6;
    localparam [7:0] ST_LISTEN_WAIT = 8'd7;
    localparam [7:0] ST_POLL_DELAY  = 8'd8;
    localparam [7:0] ST_RSR_H_ISSUE = 8'd9;
    localparam [7:0] ST_RSR_H_WAIT  = 8'd10;
    localparam [7:0] ST_RSR_L_ISSUE = 8'd11;
    localparam [7:0] ST_RSR_L_WAIT  = 8'd12;
    localparam [7:0] ST_RD_H_ISSUE  = 8'd13;
    localparam [7:0] ST_RD_H_WAIT   = 8'd14;
    localparam [7:0] ST_RD_L_ISSUE  = 8'd15;
    localparam [7:0] ST_RD_L_WAIT   = 8'd16;
    localparam [7:0] ST_REQ_ISSUE   = 8'd17;
    localparam [7:0] ST_REQ_WAIT    = 8'd18;
    localparam [7:0] ST_RXRD_H_ISSUE= 8'd19;
    localparam [7:0] ST_RXRD_H_WAIT = 8'd20;
    localparam [7:0] ST_RXRD_L_ISSUE= 8'd21;
    localparam [7:0] ST_RXRD_L_WAIT = 8'd22;
    localparam [7:0] ST_RECV_ISSUE  = 8'd23;
    localparam [7:0] ST_RECV_WAIT   = 8'd24;
    localparam [7:0] ST_PARSE       = 8'd25;
    localparam [7:0] ST_FSR_H_ISSUE = 8'd26;
    localparam [7:0] ST_FSR_H_WAIT  = 8'd27;
    localparam [7:0] ST_FSR_L_ISSUE = 8'd28;
    localparam [7:0] ST_FSR_L_WAIT  = 8'd29;
    localparam [7:0] ST_WR_H_ISSUE  = 8'd30;
    localparam [7:0] ST_WR_H_WAIT   = 8'd31;
    localparam [7:0] ST_WR_L_ISSUE  = 8'd32;
    localparam [7:0] ST_WR_L_WAIT   = 8'd33;
    localparam [7:0] ST_RESP_ISSUE  = 8'd34;
    localparam [7:0] ST_RESP_WAIT   = 8'd35;
    localparam [7:0] ST_TXWR_H_ISSUE= 8'd36;
    localparam [7:0] ST_TXWR_H_WAIT = 8'd37;
    localparam [7:0] ST_TXWR_L_ISSUE= 8'd38;
    localparam [7:0] ST_TXWR_L_WAIT = 8'd39;
    localparam [7:0] ST_SEND_ISSUE  = 8'd40;
    localparam [7:0] ST_SEND_WAIT   = 8'd41;
    localparam [7:0] ST_SEND_POLL_ISSUE = 8'd42;
    localparam [7:0] ST_SEND_POLL_WAIT  = 8'd43;
    localparam [7:0] ST_SEND_IR_ISSUE = 8'd44;
    localparam [7:0] ST_SEND_IR_WAIT  = 8'd45;
    localparam [7:0] ST_SEND_IR_CLEAR = 8'd46;
    localparam [7:0] ST_BURST_START   = 8'd47;
    localparam [7:0] ST_BURST_WAIT    = 8'd48;

    localparam [4:0] SOCK_REG = 5'h05;
    localparam [4:0] SOCK_TX  = 5'h06;
    localparam [4:0] SOCK_RX  = 5'h07;
    localparam integer MAX_REQ = 64;
    localparam integer PAGE_LEN = PAGE_RESPONSE_LEN;
    localparam integer CMD_LEN = CMD_RESPONSE_LEN;

    reg [7:0] state, cfg_index;
    reg [31:0] delay_count;
    reg [7:0] rx_rsr_hi, fsr_hi, req_index;
    reg [15:0] rx_size, rx_rd, tx_fsr, tx_wr, resp_len;
    reg [11:0] rom_addr;
    wire [7:0] rom_data;
    reg [7:0] request [0:MAX_REQ-1];
    reg [7:0] response_kind;
    reg [15:0] response_index;
    reg [15:0] next_rx_rd, next_tx_wr;
    reg [7:0] burst_sent;
    integer i;

    w5500_web_rom #(.INIT_FILE(WEB_INIT_FILE)) u_web_rom(.address(rom_addr), .data(rom_data));

    function automatic [7:0] cmd_response_byte;
        input [15:0] index;
        begin
            // HTTP 200, plain text "OK\n" with a persistent connection.
            case (index)
                0: cmd_response_byte = "H"; 1: cmd_response_byte = "T";
                2: cmd_response_byte = "T"; 3: cmd_response_byte = "P";
                4: cmd_response_byte = "/"; 5: cmd_response_byte = "1";
                6: cmd_response_byte = "."; 7: cmd_response_byte = "1";
                8: cmd_response_byte = " "; 9: cmd_response_byte = "2";
                10: cmd_response_byte = "0"; 11: cmd_response_byte = "0";
                12: cmd_response_byte = " "; 13: cmd_response_byte = "O";
                14: cmd_response_byte = "K"; 15: cmd_response_byte = 8'h0d;
                16: cmd_response_byte = 8'h0a; 17: cmd_response_byte = "C";
                18: cmd_response_byte = "o"; 19: cmd_response_byte = "n";
                20: cmd_response_byte = "t"; 21: cmd_response_byte = "e";
                22: cmd_response_byte = "n"; 23: cmd_response_byte = "t";
                24: cmd_response_byte = "-"; 25: cmd_response_byte = "T";
                26: cmd_response_byte = "y"; 27: cmd_response_byte = "p";
                28: cmd_response_byte = "e"; 29: cmd_response_byte = ":";
                30: cmd_response_byte = " "; 31: cmd_response_byte = "t";
                32: cmd_response_byte = "e"; 33: cmd_response_byte = "x";
                34: cmd_response_byte = "t"; 35: cmd_response_byte = "/";
                36: cmd_response_byte = "p"; 37: cmd_response_byte = "l";
                38: cmd_response_byte = "a"; 39: cmd_response_byte = "i";
                40: cmd_response_byte = "n"; 41: cmd_response_byte = 8'h0d;
                42: cmd_response_byte = 8'h0a; 43: cmd_response_byte = "C";
                44: cmd_response_byte = "o"; 45: cmd_response_byte = "n";
                46: cmd_response_byte = "t"; 47: cmd_response_byte = "e";
                48: cmd_response_byte = "n"; 49: cmd_response_byte = "t";
                50: cmd_response_byte = "-"; 51: cmd_response_byte = "L";
                52: cmd_response_byte = "e"; 53: cmd_response_byte = "n";
                54: cmd_response_byte = "g"; 55: cmd_response_byte = "t";
                56: cmd_response_byte = "h"; 57: cmd_response_byte = ":";
                58: cmd_response_byte = " "; 59: cmd_response_byte = "0";
                60: cmd_response_byte = 8'h0d; 61: cmd_response_byte = 8'h0a;
                62: cmd_response_byte = "C"; 63: cmd_response_byte = "o";
                64: cmd_response_byte = "n"; 65: cmd_response_byte = "n";
                66: cmd_response_byte = "e"; 67: cmd_response_byte = "c";
                68: cmd_response_byte = "t"; 69: cmd_response_byte = "i";
                70: cmd_response_byte = "o"; 71: cmd_response_byte = "n";
                72: cmd_response_byte = ":"; 73: cmd_response_byte = " ";
                74: cmd_response_byte = "k"; 75: cmd_response_byte = "e";
                76: cmd_response_byte = "e"; 77: cmd_response_byte = "p";
                78: cmd_response_byte = "-"; 79: cmd_response_byte = "a";
                80: cmd_response_byte = "l"; 81: cmd_response_byte = "i";
                82: cmd_response_byte = "v"; 83: cmd_response_byte = "e";
                84: cmd_response_byte = 8'h0d; 85: cmd_response_byte = 8'h0a;
                86: cmd_response_byte = 8'h0d; 87: cmd_response_byte = 8'h0a;
                default: cmd_response_byte = 8'h20;
            endcase
        end
    endfunction

    wire [7:0] response_byte = (response_kind == 8'd0) ? rom_data : cmd_response_byte(response_index);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_CFG_ISSUE;
            cfg_index <= 0;
            delay_count <= 0;
            xfer_start <= 0;
            xfer_write <= 0;
            xfer_addr <= 0;
            xfer_block <= 0;
            xfer_wdata <= 0;
            burst_start <= 1'b0;
            burst_write <= 1'b0;
            burst_addr <= 16'd0;
            burst_block <= 5'd0;
            burst_len <= 8'd0;
            burst_tx_valid <= 1'b0;
            burst_tx_data <= 8'd0;
            cmd_next <= 0;
            cmd_auto_toggle <= 0;
            cmd_notice <= 0;
            cmd_emergency <= 0;
            cmd_clear <= 0;
            cmd_brightness_up <= 0;
            cmd_brightness_down <= 0;
            cmd_audio_toggle <= 0;
            cmd_ui_toggle <= 0;
            rx_rsr_hi <= 0;
            rx_size <= 0;
            rx_rd <= 0;
            fsr_hi <= 0;
            tx_fsr <= 0;
            tx_wr <= 0;
            resp_len <= 0;
            response_kind <= 0;
            response_index <= 0;
            next_rx_rd <= 0;
            next_tx_wr <= 0;
            req_index <= 0;
            rom_addr <= 0;
            for (i = 0; i < MAX_REQ; i = i + 1)
                request[i] <= 0;
        end else begin
            xfer_start <= 0;
            burst_start <= 1'b0;
            burst_tx_valid <= 1'b0;
            cmd_next <= 0;
            cmd_auto_toggle <= 0;
            cmd_notice <= 0;
            cmd_emergency <= 0;
            cmd_clear <= 0;
            cmd_brightness_up <= 0;
            cmd_brightness_down <= 0;
            cmd_audio_toggle <= 0;
            cmd_ui_toggle <= 0;

            case (state)
                ST_CFG_ISSUE: begin
                    xfer_write <= 1;
                    xfer_block <= SOCK_REG;
                    case (cfg_index)
                        0: begin xfer_addr <= 16'h0000; xfer_wdata <= 8'h01; end
                        1: begin xfer_addr <= 16'h001e; xfer_wdata <= 8'h02; end
                        2: begin xfer_addr <= 16'h001f; xfer_wdata <= 8'h04; end
                        3: begin xfer_addr <= 16'h0004; xfer_wdata <= 8'h00; end
                        4: begin xfer_addr <= 16'h0005; xfer_wdata <= 8'h50; end
                        5: begin xfer_addr <= 16'h0018; xfer_block <= 5'h00; xfer_wdata <= 8'h03; end
                        default: begin xfer_addr <= 16'h002c; xfer_wdata <= 8'h04; end
                    endcase
                    xfer_start <= 1;
                    state <= ST_CFG_WAIT;
                end
                ST_CFG_WAIT: if (xfer_done) begin
                    if (cfg_index == 6) state <= ST_OPEN_ISSUE;
                    else begin cfg_index <= cfg_index + 1'b1; state <= ST_CFG_ISSUE; end
                end
                ST_OPEN_ISSUE: begin
                    xfer_write <= 1; xfer_addr <= 16'h0001; xfer_block <= SOCK_REG;
                    xfer_wdata <= 8'h01; xfer_start <= 1; state <= ST_OPEN_WAIT;
                end
                ST_OPEN_WAIT: if (xfer_done) state <= ST_SR_ISSUE;
                ST_SR_ISSUE: begin
                    xfer_write <= 0; xfer_addr <= 16'h0003; xfer_block <= SOCK_REG;
                    xfer_start <= 1; state <= ST_SR_WAIT;
                end
                ST_SR_WAIT: if (xfer_done) begin
                    if (xfer_rdata == 8'h00) state <= ST_OPEN_ISSUE;
                    else if (xfer_rdata == 8'h13) state <= ST_LISTEN_ISSUE;
                    else if (xfer_rdata == 8'h14) state <= ST_POLL_DELAY;
                    else if (xfer_rdata == 8'h17) state <= ST_RSR_H_ISSUE;
                    else state <= ST_SR_ISSUE;
                end
                ST_LISTEN_ISSUE: begin
                    xfer_write <= 1; xfer_addr <= 16'h0001; xfer_block <= SOCK_REG;
                    xfer_wdata <= 8'h02; xfer_start <= 1; state <= ST_LISTEN_WAIT;
                end
                ST_LISTEN_WAIT: if (xfer_done) state <= ST_POLL_DELAY;
                ST_POLL_DELAY: begin
                    if (delay_count >= POLL_CYCLES-1) begin
                        delay_count <= 0; state <= ST_SR_ISSUE;
                    end else delay_count <= delay_count + 1'b1;
                end
                ST_RSR_H_ISSUE: begin
                    xfer_write <= 0; xfer_addr <= 16'h0026; xfer_block <= SOCK_REG;
                    xfer_start <= 1; state <= ST_RSR_H_WAIT;
                end
                ST_RSR_H_WAIT: if (xfer_done) begin rx_rsr_hi <= xfer_rdata; state <= ST_RSR_L_ISSUE; end
                ST_RSR_L_ISSUE: begin
                    xfer_write <= 0; xfer_addr <= 16'h0027; xfer_block <= SOCK_REG;
                    xfer_start <= 1; state <= ST_RSR_L_WAIT;
                end
                ST_RSR_L_WAIT: if (xfer_done) begin
                    rx_size <= {rx_rsr_hi, xfer_rdata};
                    if ({rx_rsr_hi, xfer_rdata} != 0) state <= ST_RD_H_ISSUE;
                    else state <= ST_POLL_DELAY;
                end
                ST_RD_H_ISSUE: begin
                    xfer_write <= 0; xfer_addr <= 16'h0028; xfer_block <= SOCK_REG;
                    xfer_start <= 1; state <= ST_RD_H_WAIT;
                end
                ST_RD_H_WAIT: if (xfer_done) begin rx_rd[15:8] <= xfer_rdata; state <= ST_RD_L_ISSUE; end
                ST_RD_L_ISSUE: begin
                    xfer_write <= 0; xfer_addr <= 16'h0029; xfer_block <= SOCK_REG;
                    xfer_start <= 1; state <= ST_RD_L_WAIT;
                end
                ST_RD_L_WAIT: if (xfer_done) begin
                    rx_rd[7:0] <= xfer_rdata;
                    req_index <= 0;
                    state <= ST_REQ_ISSUE;
                end
                ST_REQ_ISSUE: begin
                    xfer_write <= 0; xfer_addr <= rx_rd + req_index; xfer_block <= SOCK_RX;
                    xfer_start <= 1; state <= ST_REQ_WAIT;
                end
                ST_REQ_WAIT: if (xfer_done) begin
                    request[req_index] <= xfer_rdata;
                    if (req_index + 1 >= ((rx_size > MAX_REQ) ? MAX_REQ : rx_size)) begin
                        next_rx_rd <= rx_rd + rx_size;
                        state <= ST_RXRD_H_ISSUE;
                    end else begin req_index <= req_index + 1'b1; state <= ST_REQ_ISSUE; end
                end
                ST_RXRD_H_ISSUE: begin
                    xfer_write <= 1; xfer_addr <= 16'h0028; xfer_block <= SOCK_REG;
                    xfer_wdata <= next_rx_rd[15:8]; xfer_start <= 1; state <= ST_RXRD_H_WAIT;
                end
                ST_RXRD_H_WAIT: if (xfer_done) state <= ST_RXRD_L_ISSUE;
                ST_RXRD_L_ISSUE: begin
                    xfer_write <= 1; xfer_addr <= 16'h0029; xfer_block <= SOCK_REG;
                    xfer_wdata <= next_rx_rd[7:0]; xfer_start <= 1; state <= ST_RXRD_L_WAIT;
                end
                ST_RXRD_L_WAIT: if (xfer_done) state <= ST_RECV_ISSUE;
                ST_RECV_ISSUE: begin
                    xfer_write <= 1; xfer_addr <= 16'h0001; xfer_block <= SOCK_REG;
                    xfer_wdata <= 8'h40; xfer_start <= 1; state <= ST_RECV_WAIT;
                end
                ST_RECV_WAIT: if (xfer_done) state <= ST_PARSE;
                ST_PARSE: begin
                    response_kind <= 8'd1;
                    resp_len <= CMD_LEN;
                    if (request[4] == "/" && request[5] == " " ) begin
                        response_kind <= 8'd0;
                        resp_len <= PAGE_LEN;
                    end else if (request[4] == "/" && request[5] == "c" && request[6] == "/") begin
                        case (request[7])
                            "n": cmd_next <= 1'b1;
                            "a": cmd_auto_toggle <= 1'b1;
                            "p": cmd_notice <= 1'b1;
                            "e": cmd_emergency <= 1'b1;
                            "x": cmd_clear <= 1'b1;
                            "u": cmd_brightness_up <= 1'b1;
                            "d": cmd_brightness_down <= 1'b1;
                            "m": cmd_audio_toggle <= 1'b1;
                            "v": cmd_ui_toggle <= 1'b1;
                            default: ;
                        endcase
                    end
                    response_index <= 0;
                    state <= ST_FSR_H_ISSUE;
                end
                ST_FSR_H_ISSUE: begin
                    xfer_write <= 0; xfer_addr <= 16'h0020; xfer_block <= SOCK_REG;
                    xfer_start <= 1; state <= ST_FSR_H_WAIT;
                end
                ST_FSR_H_WAIT: if (xfer_done) begin fsr_hi <= xfer_rdata; state <= ST_FSR_L_ISSUE; end
                ST_FSR_L_ISSUE: begin
                    xfer_write <= 0; xfer_addr <= 16'h0021; xfer_block <= SOCK_REG;
                    xfer_start <= 1; state <= ST_FSR_L_WAIT;
                end
                ST_FSR_L_WAIT: if (xfer_done) begin
                    tx_fsr <= {fsr_hi, xfer_rdata};
                    if ({fsr_hi, xfer_rdata} >= resp_len) state <= ST_WR_H_ISSUE;
                    else state <= ST_FSR_H_ISSUE;
                end
                ST_WR_H_ISSUE: begin
                    xfer_write <= 0; xfer_addr <= 16'h0024; xfer_block <= SOCK_REG;
                    xfer_start <= 1; state <= ST_WR_H_WAIT;
                end
                ST_WR_H_WAIT: if (xfer_done) begin tx_wr[15:8] <= xfer_rdata; state <= ST_WR_L_ISSUE; end
                ST_WR_L_ISSUE: begin
                    xfer_write <= 0; xfer_addr <= 16'h0025; xfer_block <= SOCK_REG;
                    xfer_start <= 1; state <= ST_WR_L_WAIT;
                end
                ST_WR_L_WAIT: if (xfer_done) begin
                    tx_wr[7:0] <= xfer_rdata;
                    response_index <= 0;
                    rom_addr <= 0;
                    burst_sent <= 0;
                    state <= ST_BURST_START;
                end
                ST_BURST_START: begin
                    burst_write <= 1'b1;
                    burst_addr <= tx_wr + response_index;
                    burst_block <= SOCK_TX;
                    burst_len <= ((resp_len - response_index) > 16'd255) ? 8'd255 : (resp_len - response_index);
                    burst_start <= 1'b1;
                    burst_sent <= 8'd0;
                    state <= ST_BURST_WAIT;
                end
                ST_BURST_WAIT: begin
                    burst_tx_valid <= 1'b1;
                    burst_tx_data <= response_byte;
                    if (burst_tx_ready) begin
                        response_index <= response_index + 1'b1;
                        burst_sent <= burst_sent + 1'b1;
                        if (response_kind == 8'd0)
                            rom_addr <= response_index + 1'b1;
                    end
                    if (burst_done) begin
                        next_tx_wr <= tx_wr + response_index;
                        if (response_index >= resp_len)
                            state <= ST_TXWR_H_ISSUE;
                        else
                            state <= ST_BURST_START;
                    end
                end
                ST_RESP_ISSUE: begin
                    xfer_write <= 1; xfer_addr <= tx_wr + response_index; xfer_block <= SOCK_TX;
                    xfer_wdata <= response_byte; xfer_start <= 1; state <= ST_RESP_WAIT;
                end
                ST_RESP_WAIT: if (xfer_done) begin
                    if (response_index + 1 >= resp_len) begin
                        next_tx_wr <= tx_wr + resp_len;
                        state <= ST_TXWR_H_ISSUE;
                    end else begin
                        response_index <= response_index + 1'b1;
                        if (response_kind == 0)
                            rom_addr <= response_index + 1'b1;
                        state <= ST_RESP_ISSUE;
                    end
                end
                ST_TXWR_H_ISSUE: begin
                    xfer_write <= 1; xfer_addr <= 16'h0024; xfer_block <= SOCK_REG;
                    xfer_wdata <= next_tx_wr[15:8]; xfer_start <= 1; state <= ST_TXWR_H_WAIT;
                end
                ST_TXWR_H_WAIT: if (xfer_done) state <= ST_TXWR_L_ISSUE;
                ST_TXWR_L_ISSUE: begin
                    xfer_write <= 1; xfer_addr <= 16'h0025; xfer_block <= SOCK_REG;
                    xfer_wdata <= next_tx_wr[7:0]; xfer_start <= 1; state <= ST_TXWR_L_WAIT;
                end
                ST_TXWR_L_WAIT: if (xfer_done) state <= ST_SEND_ISSUE;
                ST_SEND_ISSUE: begin
                    xfer_write <= 1; xfer_addr <= 16'h0001; xfer_block <= SOCK_REG;
                    xfer_wdata <= 8'h20; xfer_start <= 1; state <= ST_SEND_WAIT;
                end
                ST_SEND_WAIT: if (xfer_done) state <= ST_SEND_POLL_ISSUE;
                ST_SEND_POLL_ISSUE: begin
                    // SEND completion is reported through Sn_IR, not Sn_SR.
                    xfer_write <= 0; xfer_addr <= 16'h0002; xfer_block <= SOCK_REG;
                    xfer_start <= 1; state <= ST_SEND_POLL_WAIT;
                end
                ST_SEND_POLL_WAIT: if (xfer_done) begin
                    if (xfer_rdata[4] || xfer_rdata[3]) state <= ST_SEND_IR_CLEAR;
                    else state <= ST_SEND_POLL_ISSUE;
                end
                ST_SEND_IR_CLEAR: begin
                    xfer_write <= 1; xfer_addr <= 16'h0002; xfer_block <= SOCK_REG;
                    xfer_wdata <= 8'h18; xfer_start <= 1; state <= ST_SEND_IR_WAIT;
                end
                ST_SEND_IR_WAIT: if (xfer_done) state <= ST_SR_ISSUE;
                default: state <= ST_CFG_ISSUE;
            endcase
        end
    end
endmodule
