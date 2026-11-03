// Fixed binary command format for the first local-network demonstrator.
// [A5, version=01, sequence, opcode, arg0, arg1, reserved, CRC8-07]
module w5500_command_decoder(
    input  wire       clk,
    input  wire       rst,
    input  wire       packet_start,
    input  wire       data_valid,
    input  wire [7:0] data,
    output reg        cmd_next,
    output reg        cmd_auto_toggle,
    output reg        cmd_notice,
    output reg        cmd_emergency,
    output reg        cmd_clear,
    output reg        cmd_brightness_up,
    output reg        cmd_brightness_down,
    output reg        cmd_audio_toggle,
    output reg        cmd_ui_toggle,
    output reg        command_valid,
    output reg        command_error,
    output reg [7:0]  command_seq
);
    reg [7:0] bytes [0:7];
    reg [3:0] count;
    integer i;
    integer k;
    reg [7:0] crc;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            count               <= 4'd0;
            cmd_next            <= 1'b0;
            cmd_auto_toggle     <= 1'b0;
            cmd_notice          <= 1'b0;
            cmd_emergency       <= 1'b0;
            cmd_clear           <= 1'b0;
            cmd_brightness_up   <= 1'b0;
            cmd_brightness_down <= 1'b0;
            cmd_audio_toggle    <= 1'b0;
            cmd_ui_toggle       <= 1'b0;
            command_valid       <= 1'b0;
            command_error       <= 1'b0;
            command_seq         <= 8'd0;
            for (i = 0; i < 8; i = i + 1)
                bytes[i] <= 8'd0;
        end else begin
            cmd_next            <= 1'b0;
            cmd_auto_toggle     <= 1'b0;
            cmd_notice          <= 1'b0;
            cmd_emergency       <= 1'b0;
            cmd_clear           <= 1'b0;
            cmd_brightness_up   <= 1'b0;
            cmd_brightness_down <= 1'b0;
            cmd_audio_toggle    <= 1'b0;
            cmd_ui_toggle       <= 1'b0;
            command_valid       <= 1'b0;
            command_error       <= 1'b0;

            if (packet_start)
                count <= 4'd0;

            if (data_valid && (count < 8)) begin
                bytes[count] <= data;
                if (count == 7) begin
                    crc = 8'd0;
                    for (i = 0; i < 7; i = i + 1) begin
                        crc = crc ^ ((i == count) ? data : bytes[i]);
                        for (k = 0; k < 8; k = k + 1)
                            crc = crc[7] ? ((crc << 1) ^ 8'h07) : (crc << 1);
                    end
                    if ((bytes[0] == 8'ha5) && (bytes[1] == 8'h01) &&
                        (crc == data)) begin
                        command_seq   <= bytes[2];
                        command_valid <= 1'b1;
                        case (bytes[3])
                            8'h10: cmd_next            <= 1'b1;
                            8'h11: cmd_auto_toggle     <= 1'b1;
                            8'h12: cmd_notice          <= 1'b1;
                            8'h16: cmd_emergency       <= 1'b1;
                            8'h13: cmd_clear           <= 1'b1;
                            8'h14: cmd_brightness_up   <= 1'b1;
                            8'h15: cmd_brightness_down <= 1'b1;
                            8'h22: cmd_audio_toggle    <= 1'b1;
                            8'h23: cmd_ui_toggle       <= 1'b1;
                            default: begin
                                command_valid <= 1'b0;
                                command_error <= 1'b1;
                            end
                        endcase
                    end else begin
                        command_error <= 1'b1;
                    end
                end else begin
                    count <= count + 1'b1;
                end
            end
        end
    end
endmodule
