module matrix_keypad #(
    parameter integer ROW_SCAN_DIV = 12500,
    parameter integer DEBOUNCE_SCANS = 3
)(
    input  wire       clk,
    input  wire       rst,
    input  wire [3:0] rows_n,
    output reg  [3:0] cols_n,
    output reg [15:0] keys_pressed
);
    localparam integer DIV_BITS = ROW_SCAN_DIV <= 1 ? 1 : $clog2(ROW_SCAN_DIV);
    localparam integer DB_BITS = DEBOUNCE_SCANS <= 1 ? 1 : $clog2(DEBOUNCE_SCANS);

    reg [DIV_BITS-1:0] scan_count;
    reg [1:0] row_index;
    (* async_reg = "true" *) reg [3:0] rows_sync0, rows_sync1;
    reg [15:0] raw_keys;
    reg [15:0] stable_candidate;
    reg [DB_BITS-1:0] debounce_count;
    wire [15:0] frame_keys = replace_column(raw_keys, row_index, ~rows_sync1);
    wire [4:0] key_count = count_keys(frame_keys);

    function [4:0] count_keys;
        input [15:0] key_vector;
        integer key_index;
        begin
            count_keys = 0;
            for (key_index = 0; key_index < 16; key_index = key_index + 1)
                count_keys = count_keys + key_vector[key_index];
        end
    endfunction

    function [15:0] replace_column;
        input [15:0] bitmap;
        input [1:0] column_index;
        input [3:0] pressed_rows;
        integer row_index;
        begin
            replace_column = bitmap;
            for (row_index = 0; row_index < 4; row_index = row_index + 1)
                replace_column[row_index*4+column_index] = pressed_rows[row_index];
        end
    endfunction

    always @* begin
        cols_n = 4'bzzzz;
        case (row_index)
            2'd0: cols_n[0] = 1'b0;
            2'd1: cols_n[1] = 1'b0;
            2'd2: cols_n[2] = 1'b0;
            2'd3: cols_n[3] = 1'b0;
        endcase

    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            scan_count <= 0;
            row_index <= 0;
            rows_sync0 <= 4'b1111;
            rows_sync1 <= 4'b1111;
            raw_keys <= 0;
            stable_candidate <= 0;
            debounce_count <= 0;
            keys_pressed <= 0;
        end else begin
            rows_sync0 <= rows_n;
            rows_sync1 <= rows_sync0;

            if (ROW_SCAN_DIV <= 1 || scan_count == ROW_SCAN_DIV - 1) begin
                scan_count <= 0;
                case (row_index)
                    2'd0: begin
                        raw_keys[0] <= ~rows_sync1[0]; raw_keys[4] <= ~rows_sync1[1];
                        raw_keys[8] <= ~rows_sync1[2]; raw_keys[12] <= ~rows_sync1[3];
                    end
                    2'd1: begin
                        raw_keys[1] <= ~rows_sync1[0]; raw_keys[5] <= ~rows_sync1[1];
                        raw_keys[9] <= ~rows_sync1[2]; raw_keys[13] <= ~rows_sync1[3];
                    end
                    2'd2: begin
                        raw_keys[2] <= ~rows_sync1[0]; raw_keys[6] <= ~rows_sync1[1];
                        raw_keys[10] <= ~rows_sync1[2]; raw_keys[14] <= ~rows_sync1[3];
                    end
                    default: begin
                        raw_keys[3] <= ~rows_sync1[0]; raw_keys[7] <= ~rows_sync1[1];
                        raw_keys[11] <= ~rows_sync1[2]; raw_keys[15] <= ~rows_sync1[3];
                        row_index <= 0;
                        if (key_count <= 1) begin
                            if (frame_keys == keys_pressed) begin
                                stable_candidate <= frame_keys;
                                debounce_count <= 0;
                            end else if (DEBOUNCE_SCANS <= 1) begin
                                stable_candidate <= frame_keys;
                                keys_pressed <= frame_keys;
                                debounce_count <= 0;
                            end else if (frame_keys != stable_candidate) begin
                                // Start a new run when the raw key changes.
                                // Only identical consecutive scans may commit.
                                stable_candidate <= frame_keys;
                                debounce_count <= 1;
                            end else if (debounce_count == DEBOUNCE_SCANS - 1) begin
                                keys_pressed <= frame_keys;
                                debounce_count <= 0;
                            end else begin
                                debounce_count <= debounce_count + 1'b1;
                            end
                        end else begin
                            stable_candidate <= keys_pressed;
                            debounce_count <= 0;
                        end
                    end
                endcase
                if (row_index != 2'd3)
                    row_index <= row_index + 1'b1;
            end else begin
                scan_count <= scan_count + 1'b1;
            end
        end
    end
endmodule
