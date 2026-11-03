// Little-endian snapshots; 115200 8N1, <=20 changes/s + 1 Hz heartbeat.
// Default v1: 24 bytes. INCLUDE_STORAGE=1 defaults to v2, 64 bytes.
// STATUS_VERSION=3 identifies E3/M5 fields in bytes 60..62 without making a
// legacy v2 packet's reserved zeros look like a 25% brightness setting.
// Layout is documented in SLIDESHOW_DIAGNOSTICS.md. Final byte is payload XOR.
// Bytes: A5 33 01 scene flags requested requests[4] ignored[4] commits[4]
//        last_event_latency[4] last_event_scene xor_of_previous_23_bytes.
module scene_status_uart #(
    parameter integer CLK_FREQ_HZ = 25000000,
    parameter integer BAUD_RATE = 115200,
    parameter integer MIN_GAP_CYCLES = CLK_FREQ_HZ / 20,
    parameter integer HEARTBEAT_CYCLES = CLK_FREQ_HZ,
    parameter integer INCLUDE_STORAGE = 0,
    parameter integer STATUS_VERSION = 0
)(
    input wire clk, rst,
    input wire [1:0] scene_id, requested_scene_id, last_event_scene,
    input wire request_pending, latency_valid,
    input wire [31:0] request_count, ignored_count, commit_count, latency_cycles,
    input wire [319:0] storage_status,
    output reg tx
);
    localparam integer DIVISOR = CLK_FREQ_HZ / BAUD_RATE;
    localparam integer BIT_COUNT_BITS = DIVISOR <= 1 ? 1 : $clog2(DIVISOR);
    localparam integer GAP_BITS = HEARTBEAT_CYCLES <= 1 ? 1 : $clog2(HEARTBEAT_CYCLES+1);
    localparam integer PAYLOAD_BYTES = INCLUDE_STORAGE ? 63 : 23;
    localparam integer PAYLOAD_BITS = PAYLOAD_BYTES * 8;
    localparam [7:0] PACKET_VERSION = STATUS_VERSION == 0 ?
        (INCLUDE_STORAGE ? 8'h02 : 8'h01) : STATUS_VERSION;
    wire [183:0] scene_payload = {6'd0, last_event_scene, latency_cycles,
        commit_count, ignored_count, request_count, 6'd0, requested_scene_id,
        6'd0, latency_valid, request_pending, 6'd0, scene_id,
        PACKET_VERSION, 8'h33, 8'ha5};
    wire [PAYLOAD_BITS-1:0] live = INCLUDE_STORAGE ?
        {storage_status,scene_payload} : scene_payload;
    reg [PAYLOAD_BITS-1:0] shift, last_sent;
    reg [7:0] checksum;
    reg [GAP_BITS-1:0] gap;
    reg [BIT_COUNT_BITS-1:0] bit_clock;
    reg [5:0] byte_index;
    reg [3:0] bit_index;
    reg busy, sent_once;
    wire [7:0] byte_data = byte_index == PAYLOAD_BYTES ? checksum : shift[7:0];
    function [7:0] packet_xor;
        input [PAYLOAD_BITS-1:0] data;
        integer i;
        begin
            packet_xor=0;
            for (i=0; i<PAYLOAD_BYTES; i=i+1) packet_xor=packet_xor ^ data[i*8 +: 8];
        end
    endfunction
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tx<=1; shift<=0; last_sent<=0; checksum<=0;
            gap<=0; bit_clock<=0; byte_index<=0; bit_index<=0;
            busy<=0; sent_once<=0;
        end else begin
            if (gap < HEARTBEAT_CYCLES) gap<=gap+1'b1;
            if (!busy) begin
                tx<=1;
                if (!sent_once || gap >= HEARTBEAT_CYCLES ||
                    (gap >= MIN_GAP_CYCLES && live != last_sent)) begin
                    shift<=live; last_sent<=live; checksum<=packet_xor(live);
                    gap<=0; bit_clock<=0; byte_index<=0; bit_index<=0;
                    busy<=1; sent_once<=1; tx<=0;
                end
            end else if (bit_clock == DIVISOR-1) begin
                bit_clock<=0;
                if (bit_index < 8) begin
                    tx<=byte_data[bit_index]; bit_index<=bit_index+1'b1;
                end else if (bit_index == 8) begin
                    tx<=1; bit_index<=9;
                end else if (byte_index == PAYLOAD_BYTES) begin
                    tx<=1; busy<=0;
                end else begin
                    byte_index<=byte_index+1'b1;
                    shift<=shift >> 8; bit_index<=0; tx<=0;
                end
            end else bit_clock<=bit_clock+1'b1;
        end
    end
endmodule
