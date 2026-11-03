`timescale 1ns/1ps
module keypad_brightness_tb;
 reg clk=0,control_clk=0,rst=1;
 reg [15:0] pressed_keys=0;
 reg [3:0] rows_n;
 wire [3:0] cols_n;
 wire [15:0] keys_pressed;
 wire [1:0] brightness;
 wire mode,audio;
 matrix_keypad #(.ROW_SCAN_DIV(6),.DEBOUNCE_SCANS(3)) scanner(clk,rst,rows_n,cols_n,keys_pressed);
 display_parameter_ctrl #(.DEBOUNCE_CYCLES(3)) ctrl(
  .clk(control_clk),.rst(rst),.sw_audio_enable(1'b0),
  .key_down_n(~keys_pressed[5]),.key_up_n(~keys_pressed[4]),
  .adjust_mode(mode),.brightness_level(brightness),.audio_enable(audio));
 always #5 clk=~clk;
 always #7 control_clk=~control_clk;
    function [3:0] derive_rows;
        input [3:0] selected_cols_n;
        input [15:0] keys;
        integer row_index, col_index;
        begin
            derive_rows = 4'b1111;
            for (col_index = 0; col_index < 4; col_index = col_index + 1)
                if (!selected_cols_n[col_index])
                    for (row_index = 0; row_index < 4; row_index = row_index + 1)
                        if (keys[row_index*4+col_index]) derive_rows[row_index] = 1'b0;
        end
    endfunction

    always @* rows_n = derive_rows(cols_n, pressed_keys);

    task clocks;
        input integer count;
        integer i;
        begin
            for (i = 0; i < count; i = i + 1) begin
                @(posedge clk); #1;
            end
        end
    endtask


 task press;input [15:0] mask;begin pressed_keys=mask;clocks(500);pressed_keys=0;clocks(500);end endtask
 initial begin
  clocks(5);rst=0;clocks(500);
  press(16'h0020);if(brightness!==2)$fatal(1,"S6 row2 col2 must lower brightness");
  press(16'h0010);if(brightness!==3)$fatal(1,"S5 row2 col1 must raise brightness");
  press(16'h0001);press(16'h0002);press(16'h0004);press(16'h0008);
  if(brightness!==3)$fatal(1,"S1-S4 affected brightness");
  press(16'h0030);if(brightness!==3)$fatal(1,"matrix chord not suppressed");
  pressed_keys=16'h0020;clocks(2000);if(brightness!==2)$fatal(1,"held S6 repeated");
  pressed_keys=0;clocks(500);press(16'h0020);if(brightness!==1)$fatal(1,"S6 repress failed");
  if(mode!==0)$fatal(1,"mode activated");
  $display("PASS: physical matrix S5/S6 mapping, unrelated keys, chord, hold, independent control clock");$finish;
 end
 initial begin #500000;$fatal(1,"timeout");end
endmodule
