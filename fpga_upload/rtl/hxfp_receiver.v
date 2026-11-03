// HXFP/1 UDP application receiver, paired with desktop/fpga_transfer.py.
// No W5500 register ownership here: connect to the latest project's datagram API.
// All ports are synchronous to clk. A datagram start precedes its first byte;
// datagram end follows its last byte (one cycle separation). rx_peer={IPv4,port}.
// Frame sink MUST reserve an offscreen buffer, provide FIFO backpressure, and
// assert commit_ready only AFTER memory drain + safe display-frame commit.
module hxfp_receiver #(
    parameter integer WIDTH = 640,
    parameter integer HEIGHT = 480,
    parameter integer MAX_CHUNK = 1024,
    parameter integer TIMEOUT_CYCLES = 1500000000
)(
    input wire clk, input wire rst,
    output wire rx_ready,
    input wire rx_start, input wire rx_valid, input wire [7:0] rx_data,
    input wire rx_end, input wire [47:0] rx_peer,
    output wire tx_valid, input wire tx_ready,
    output wire [7:0] tx_data, output wire tx_last,
    output reg [47:0] tx_peer,
    output wire frame_begin, input wire frame_begin_ready,
    output wire pixel_valid, input wire pixel_ready,
    output wire [31:0] pixel_address, output wire [15:0] pixel_rgb565,
    output wire frame_commit, input wire frame_commit_ready,
    output reg frame_abort, input wire frame_error,
    output reg transfer_active,
    output wire [31:0] received_bytes,
    output reg [31:0] displayed_frames
);
    localparam integer TOTAL_BYTES = WIDTH * HEIGHT * 2;
    localparam [3:0] RX=0, CHECK=1, DISPATCH=2, ALLOCATE=3, WRITE=4,
                     COMMIT_WAIT=5, TX_CRC=6, TX_SEND=7, WRITE_FETCH=8, WRITE_LOW=9;
    reg [3:0] state;
    reg collecting, overflowed;
    reg [10:0] rx_count;
    reg [7:0] header [0:19];
    reg [7:0] metadata [0:11];
    (* ram_style="bram" *) reg [15:0] pixel_memory [0:MAX_CHUNK/2-1];
    reg [7:0] pixel_low;
    reg [15:0] pixel_word;
    reg [31:0] packet_crc;
    reg [47:0] packet_peer, owner_peer;
    reg [31:0] owner_session, expected_image_crc, image_crc;
    // Even legal two-byte DATA packets need at most 307200 sequence numbers.
    reg [18:0] next_sequence_count;
    wire [31:0] next_sequence={13'd0,next_sequence_count};
    reg [19:0] accepted_bytes;
    assign received_bytes={12'd0,accepted_bytes};
    reg [31:0] previous_packet_crc;
    reg [15:0] previous_length;
    reg [9:0] write_pos;
    reg completed;
    reg [31:0] completed_sequence;
    reg [30:0] watchdog;
    reg [7:0] reply_op, reply_status, reply_phase;
    reg [31:0] reply_session, reply_sequence, reply_received, reply_image_crc;
    reg [31:0] reply_crc;
    reg [31:0] pixel_low_crc;
    reg [5:0] tx_index;
    localparam integer PACKET_AW=$clog2(MAX_CHUNK/2);
    wire [PACKET_AW-1:0] packet_write_address=(rx_count-20)>>1;
    wire [PACKET_AW-1:0] packet_read_address=write_pos>>1;
    always @(posedge clk) begin
        if (state==RX && collecting && rx_valid && rx_count>=20 && rx_count<20+MAX_CHUNK && rx_count[0])
            pixel_memory[packet_write_address] <= {rx_data,pixel_low};
        pixel_word <= pixel_memory[packet_read_address];
    end
    wire [31:0] request_session = {header[6],header[7],header[8],header[9]};
    wire [31:0] request_sequence = {header[10],header[11],header[12],header[13]};
    wire [15:0] request_length = {header[14],header[15]};
    wire [31:0] request_crc = {header[16],header[17],header[18],header[19]};
    wire owner_matches = request_session == owner_session && packet_peer == owner_peer;
    wire [31:0] metadata_crc = {metadata[8],metadata[9],metadata[10],metadata[11]};
    wire [31:0] metadata_length = {metadata[4],metadata[5],metadata[6],metadata[7]};

    function [31:0] crc_byte;
        input [31:0] c;
        input [7:0] b;
        reg [31:0] v;
        integer k;
        begin
            v = c ^ b;
            for (k=0;k<8;k=k+1)
                v = v[0] ? ((v >> 1) ^ 32'hedb88320) : (v >> 1);
            crc_byte = v;
        end
    endfunction

    // One CRC datapath serves packet RX, pixel prefix and ACK generation in
    // mutually exclusive states. One extra pixel beat avoids three CRC units.
    wire [31:0] crc_input = state==RX ? packet_crc :
        (state==WRITE_LOW ? image_crc : (state==WRITE ? pixel_low_crc : reply_crc));
    wire [7:0] crc_data = state==RX ? rx_data :
        (state==WRITE_LOW ? pixel_word[7:0] : (state==WRITE ? pixel_word[15:8] : reply_byte(tx_index)));
    wire [31:0] crc_result=crc_byte(crc_input,crc_data);
    wire [31:0] pixel_next_crc = crc_result;
    assign rx_ready = state == RX && !collecting;
    assign frame_begin = state == ALLOCATE;
    assign pixel_valid = state == WRITE;
    assign pixel_address = (received_bytes + write_pos) >> 1;
    assign pixel_rgb565 = pixel_word;
    assign frame_commit = state == COMMIT_WAIT;
    assign tx_valid = state == TX_SEND;
    assign tx_last = tx_index == 35;
    assign tx_data = reply_byte(tx_index);

    function [7:0] reply_byte;
        input [5:0] n;
        begin
            case (n)
                0: reply_byte=8'h48; 1: reply_byte=8'h58;
                2: reply_byte=8'h46; 3: reply_byte=8'h50;
                4: reply_byte=1; 5: reply_byte=reply_op;
                6: reply_byte=reply_session[31:24]; 7: reply_byte=reply_session[23:16];
                8: reply_byte=reply_session[15:8]; 9: reply_byte=reply_session[7:0];
                10: reply_byte=reply_sequence[31:24]; 11: reply_byte=reply_sequence[23:16];
                12: reply_byte=reply_sequence[15:8]; 13: reply_byte=reply_sequence[7:0];
                14: reply_byte=0; 15: reply_byte=16;
                16: reply_byte=reply_crc[31:24]; 17: reply_byte=reply_crc[23:16];
                18: reply_byte=reply_crc[15:8]; 19: reply_byte=reply_crc[7:0];
                20: reply_byte=reply_status; 21: reply_byte=reply_phase;
                22: reply_byte=(MAX_CHUNK >> 8) & 255; 23: reply_byte=MAX_CHUNK & 255;
                24: reply_byte=reply_received[31:24]; 25: reply_byte=reply_received[23:16];
                26: reply_byte=reply_received[15:8]; 27: reply_byte=reply_received[7:0];
                28: reply_byte=reply_image_crc[31:24]; 29: reply_byte=reply_image_crc[23:16];
                30: reply_byte=reply_image_crc[15:8]; 31: reply_byte=reply_image_crc[7:0];
                32: reply_byte=(WIDTH >> 8) & 255; 33: reply_byte=WIDTH & 255;
                34: reply_byte=(HEIGHT >> 8) & 255; 35: reply_byte=HEIGHT & 255;
                default: reply_byte=0;
            endcase
        end
    endfunction

    task respond;
        input [7:0] status;
        input [7:0] phase;
        input [31:0] count;
        input [31:0] crc;
        begin
            reply_op <= header[5] | 8'h80;
            reply_status <= status; reply_phase <= phase;
            reply_session <= request_session; reply_sequence <= request_sequence;
            reply_received <= count; reply_image_crc <= crc;
            reply_crc <= 32'hffffffff; tx_index <= 0;
            tx_peer <= packet_peer;
            state <= TX_CRC;
        end
    endtask

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            state<=RX; collecting<=0; overflowed<=0; rx_count<=0;
            packet_crc<=32'hffffffff; packet_peer<=0; owner_peer<=0;
            owner_session<=0; expected_image_crc<=0; image_crc<=32'hffffffff;
            next_sequence_count<=1; previous_packet_crc<=0; previous_length<=0;
            write_pos<=0; completed<=0; completed_sequence<=0; watchdog<=0;
            transfer_active<=0; accepted_bytes<=0; displayed_frames<=0;
            frame_abort<=0; reply_op<=0; reply_status<=0; reply_phase<=0;
            reply_session<=0; reply_sequence<=0; reply_received<=0;
            reply_image_crc<=0; reply_crc<=0; tx_index<=0; tx_peer<=0;
            for (i=0;i<20;i=i+1) header[i]<=0;
        end else begin
            frame_abort<=0;
            if (transfer_active || state==ALLOCATE || collecting) watchdog<=watchdog+1;
            else watchdog<=0;
            case (state)
                RX: begin
                    if (rx_start && !collecting) begin
                        collecting<=1; overflowed<=0; rx_count<=0;
                        packet_crc<=32'hffffffff; packet_peer<=rx_peer;
                    end else if (rx_valid && collecting) begin
                        if (rx_count < 20+MAX_CHUNK) begin
                            if (rx_count < 20) header[rx_count]<=rx_data;
                            else begin
                                if(rx_count<32) metadata[rx_count-20]<=rx_data;
                                if(!rx_count[0]) pixel_low<=rx_data;
                            end
                            if (rx_count < 16 || rx_count >= 20)
                                packet_crc<=crc_result;
                            rx_count<=rx_count+1;
                        end else overflowed<=1;
                    end
                    if (rx_end && collecting) begin collecting<=0; state<=CHECK; end
                end
                CHECK: begin
                    // Malformed packets are discarded without writes or replies.
                    if (overflowed || rx_count<20 || request_length>MAX_CHUNK ||
                        rx_count!=20+request_length ||
                        {header[0],header[1],header[2],header[3]}!=32'h48584650 ||
                        header[4]!=1 || request_session==0 || (~packet_crc)!=request_crc)
                        state<=RX;
                    else begin state<=DISPATCH; watchdog<=0; end
                end
                DISPATCH: begin
                    case (header[5])
                        1: begin // capability query
                            if (request_length!=0) respond(1,0,0,0);
                            else respond(0,transfer_active?1:(completed?2:0),received_bytes,~image_crc);
                        end
                        2: begin // BEGIN; fixed width/height/size/CRC descriptor
                            if (request_length!=12 || request_sequence!=0 ||
                                {metadata[0],metadata[1]}!=WIDTH || {metadata[2],metadata[3]}!=HEIGHT ||
                                metadata_length!=TOTAL_BYTES) respond(1,0,0,0);
                            else if (transfer_active) begin
                                if (owner_matches && metadata_crc==expected_image_crc)
                                    respond(0,1,received_bytes,~image_crc);
                                else respond(2,1,received_bytes,~image_crc);
                            end else if (completed && owner_matches) respond(3,2,received_bytes,~image_crc);
                            else begin
                                owner_peer<=packet_peer; owner_session<=request_session;
                                expected_image_crc<=metadata_crc; accepted_bytes<=0;
                                image_crc<=32'hffffffff; next_sequence_count<=1;
                                previous_length<=0; previous_packet_crc<=0; completed<=0;
                                state<=ALLOCATE;
                            end
                        end
                        3: begin // DATA; packets validated BEFORE pixel writes
                            if (!transfer_active || !owner_matches) respond(5,0,0,0);
                            else if (request_sequence==next_sequence-1 && previous_length!=0 &&
                                     request_crc==previous_packet_crc && request_length==previous_length)
                                respond(0,1,received_bytes,~image_crc);
                            else if (request_sequence!=next_sequence) respond(3,1,received_bytes,~image_crc);
                            else if (request_length==0 || request_length[0] ||
                                     received_bytes+request_length>TOTAL_BYTES) respond(1,1,received_bytes,~image_crc);
                            else begin write_pos<=0; state<=WRITE_FETCH; end
                        end
                        4: begin // COMMIT; ACK delayed until real frame commit
                            if (request_length!=0) respond(1,0,0,0);
                            else if (completed && owner_matches && request_sequence==completed_sequence)
                                respond(0,2,received_bytes,~image_crc);
                            else if (!transfer_active || !owner_matches) respond(5,0,0,0);
                            else if (request_sequence!=next_sequence) respond(3,1,received_bytes,~image_crc);
                            else if (received_bytes!=TOTAL_BYTES) respond(7,1,received_bytes,~image_crc);
                            else if ((~image_crc)!=expected_image_crc) respond(4,1,received_bytes,~image_crc);
                            else state<=COMMIT_WAIT;
                        end
                        5: begin // ABORT never discards an already displayed image
                            if (request_length!=0) respond(1,0,0,0);
                            else if (owner_matches && transfer_active) begin
                                frame_abort<=1; transfer_active<=0; completed<=0;
                                accepted_bytes<=0; image_crc<=32'hffffffff;
                                respond(0,0,0,0);
                            end else if (owner_matches && completed) respond(0,2,received_bytes,~image_crc);
                            else respond(5,0,0,0);
                        end
                        default: respond(8,0,0,0);
                    endcase
                end
                ALLOCATE: begin
                    if (frame_error) begin frame_abort<=1; respond(6,0,0,0); end
                    else if (frame_begin_ready) begin
                        transfer_active<=1; watchdog<=0; respond(0,1,0,0);
                    end
                end
                WRITE_FETCH: state<=WRITE_LOW;
                WRITE_LOW:begin pixel_low_crc<=crc_result;state<=WRITE;end
                WRITE: begin
                    if (frame_error) begin
                        frame_abort<=1; transfer_active<=0; respond(6,0,received_bytes,~image_crc);
                    end else if (pixel_ready) begin
                        image_crc<=pixel_next_crc; watchdog<=0;
                        if (write_pos+2==request_length) begin
                            accepted_bytes<=received_bytes+request_length;
                            previous_length<=request_length; previous_packet_crc<=request_crc;
                            next_sequence_count<=next_sequence+1;
                            respond(0,1,received_bytes+request_length,~pixel_next_crc);
                        end else begin write_pos<=write_pos+2;state<=WRITE_FETCH;end
                    end
                end
                COMMIT_WAIT: begin
                    if (frame_error) begin
                        transfer_active<=0; frame_abort<=1; respond(6,0,received_bytes,~image_crc);
                    end else if (frame_commit_ready) begin
                        transfer_active<=0; completed<=1; completed_sequence<=request_sequence;
                        displayed_frames<=displayed_frames+1; watchdog<=0;
                        respond(0,2,received_bytes,~image_crc);
                    end
                end
                TX_CRC: begin
                    if (tx_index==35) begin
                        reply_crc<=~crc_result;
                        tx_index<=0; state<=TX_SEND;
                    end else begin
                        reply_crc<=crc_result;
                        tx_index<=tx_index==15 ? 20 : tx_index+1;
                    end
                end
                TX_SEND: if (tx_ready) begin
                    if (tx_last) begin state<=RX; tx_index<=0; end
                    else tx_index<=tx_index+1;
                end
                default: state<=RX;
            endcase
            // Idle/stalled transfers are discarded; timeout never commits pixels.
            // Reply stream is allowed to finish, preserving datagram integrity.
            if (watchdog>=TIMEOUT_CYCLES-1 && state!=TX_SEND && state!=TX_CRC) begin
                transfer_active<=0; completed<=0; frame_abort<=1; collecting<=0; state<=RX;
                accepted_bytes<=0; image_crc<=32'hffffffff; watchdog<=0;
            end
        end
    end
endmodule
